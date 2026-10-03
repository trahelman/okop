"use strict";
"require form";
"require baseclass";
"require ui";
"require uci";
"require tools.widgets as widgets";
"require view.okop.main as main";
"require view.okop.outbound as outbound";

function toArray(value) {
  if (value == null || value === "") {
    return [];
  }

  return Array.isArray(value) ? value : [value];
}

function countEntries(section_id, listType, dynamicOption, textOption) {
  switch (uci.get("okop", section_id, listType)) {
    case "dynamic":
      return toArray(uci.get("okop", section_id, dynamicOption)).length;
    case "text":
      return main.parseValueList(uci.get("okop", section_id, textOption) || "")
        .length;
    default:
      return 0;
  }
}

function describeConnection(section_id) {
  const get = (option) => uci.get("okop", section_id, option);
  let line;

  switch (get("connection_type")) {
    case "outbound":
      line = get("outbound")
        ? `${get("outbound")} · ${outbound.describeConnection(get("outbound"))}`
        : _("no connection selected");
      break;
    case "block":
      line = _("Block");
      break;
    case "exclusion":
      line = _("Exclusion");
      break;
    default:
      line = _("not configured");
  }

  // An array, not a string: LuCI inserts a string child as HTML, and link names come from user input
  return E("div", {}, [line]);
}

function describeLists(section_id) {
  const get = (option) => uci.get("okop", section_id, option);
  const lines = [];

  const community = toArray(get("community_lists")).map(
    (key) => main.DOMAIN_LIST_OPTIONS[key] || key,
  );
  if (community.length) {
    lines.push(community.join(", "));
  }

  const counters = [
    [
      _("domains: %d"),
      countEntries(section_id, "user_domain_list_type", "user_domains", "user_domains_text"),
    ],
    [
      _("subnets: %d"),
      countEntries(section_id, "user_subnet_list_type", "user_subnets", "user_subnets_text"),
    ],
    [
      _("local lists: %d"),
      toArray(get("local_domain_lists")).length + toArray(get("local_subnet_lists")).length,
    ],
    [
      _("remote lists: %d"),
      toArray(get("remote_domain_lists")).length + toArray(get("remote_subnet_lists")).length,
    ],
    [_("fully routed IPs: %d"), toArray(get("fully_routed_ips")).length],
  ]
    .filter(([, count]) => count > 0)
    .map(([label, count]) => label.format(count));
  if (counters.length) {
    lines.push(counters.join(", "));
  }

  if (!lines.length) {
    return E("em", {}, _("no lists"));
  }

  // Arrays, not strings: LuCI inserts a string child as HTML, and these come from user input (link names)
  return E("div", {}, lines.map((line) => E("div", {}, [line])));
}

// Columns of the sections table, the options themselves are edited in the modal
function createSectionColumns(section) {
  section.children.forEach((option) => {
    option.modalonly = true;
  });

  let o = section.option(form.DummyValue, "_connection", _("Connection"));
  o.modalonly = false;
  o.textvalue = describeConnection;

  o = section.option(form.DummyValue, "_lists", _("Lists"));
  o.modalonly = false;
  o.textvalue = describeLists;
}

function createSectionContent(section) {
  section.tab("basic", _("Connection"));
  section.tab("lists", _("Lists"));
  section.tab("advanced", _("Advanced"));

  let o = section.taboption(
    "basic",
    form.ListValue,
    "connection_type",
    _("Connection Type"),
    _(
      "Send the traffic of the lists through a connection, block it, or let it go directly",
    ),
  );
  o.value("outbound", _("Through a connection"));
  o.value("block", _("Block"));
  o.value("exclusion", _("Exclusion"));
  o.default = "outbound";

  o = outbound.addConnectionOption(
    section,
    "basic",
    "outbound",
    _("Connection"),
    _("Connections are set up on the Outbound connections tab"),
  );
  o.depends("connection_type", "outbound");
  o.rmempty = false;

  o = section.taboption(
    "lists",
    form.DynamicList,
    "community_lists",
    _("Community Lists"),
    _("Select a predefined list for routing") +
      ' <a href="https://github.com/itdoginfo/allow-domains" target="_blank">github.com/itdoginfo/allow-domains</a>',
  );
  o.placeholder = "Service list";
  Object.entries(main.DOMAIN_LIST_OPTIONS).forEach(([key, label]) => {
    o.value(key, _(label));
  });
  o.rmempty = true;
  let lastValues = [];
  let isProcessing = false;

  o.onchange = function (ev, section_id, value) {
    if (isProcessing) return;
    isProcessing = true;

    try {
      const values = Array.isArray(value) ? value : [value];
      let newValues = [...values];
      let notifications = [];

      const selectedRegionalOptions = main.REGIONAL_OPTIONS.filter((opt) =>
        newValues.includes(opt),
      );

      if (selectedRegionalOptions.length > 1) {
        const lastSelected =
          selectedRegionalOptions[selectedRegionalOptions.length - 1];
        const removedRegions = selectedRegionalOptions.slice(0, -1);
        newValues = newValues.filter(
          (v) => v === lastSelected || !main.REGIONAL_OPTIONS.includes(v),
        );
        notifications.push(
          E("p", {}, [
            E("strong", {}, _("Regional options cannot be used together")),
            E("br"),
            _(
              "Warning: %s cannot be used together with %s. Previous selections have been removed.",
            ).format(removedRegions.join(", "), lastSelected),
          ]),
        );
      }

      if (newValues.includes("russia_inside")) {
        const removedServices = newValues.filter(
          (v) => !main.ALLOWED_WITH_RUSSIA_INSIDE.includes(v),
        );
        if (removedServices.length > 0) {
          newValues = newValues.filter((v) =>
            main.ALLOWED_WITH_RUSSIA_INSIDE.includes(v),
          );
          notifications.push(
            E("p", { class: "alert-message warning" }, [
              E("strong", {}, _("Russia inside restrictions")),
              E("br"),
              _(
                "Warning: Russia inside can only be used with %s. %s already in Russia inside and have been removed from selection.",
              ).format(
                main.ALLOWED_WITH_RUSSIA_INSIDE.map(
                  (key) => main.DOMAIN_LIST_OPTIONS[key],
                )
                  .filter((label) => label !== "Russia inside")
                  .join(", "),
                removedServices.join(", "),
              ),
            ]),
          );
        }
      }

      if (JSON.stringify(newValues.sort()) !== JSON.stringify(values.sort())) {
        this.getUIElement(section_id).setValue(newValues);
      }

      notifications.forEach((notification) =>
        ui.addNotification(null, notification),
      );
      lastValues = newValues;
    } catch (e) {
      console.error("Error in onchange handler:", e);
    } finally {
      isProcessing = false;
    }
  };

  o = section.taboption(
    "lists",
    form.ListValue,
    "user_domain_list_type",
    _("User Domain List Type"),
    _("Select the list type for adding custom domains"),
  );
  o.value("disabled", _("Disabled"));
  o.value("dynamic", _("Dynamic List"));
  o.value("text", _("Text List"));
  o.default = "disabled";
  o.rmempty = false;

  o = section.taboption(
    "lists",
    form.DynamicList,
    "user_domains",
    _("User Domains"),
    _(
      "Enter domain names without protocols, e.g. example.com or sub.example.com",
    ),
  );
  o.placeholder = "Domains list";
  o.depends("user_domain_list_type", "dynamic");
  o.rmempty = false;
  o.validate = function (section_id, value) {
    // Optional
    if (!value || value.length === 0) {
      return true;
    }

    const validation = main.validateDomain(value, true);

    if (validation.valid) {
      return true;
    }

    return validation.message;
  };

  o = section.taboption(
    "lists",
    form.TextValue,
    "user_domains_text",
    _("User Domains List"),
    _(
      "Enter domain names separated by commas, spaces, or newlines. You can add comments using //",
    ),
  );
  o.placeholder =
    "example.com, sub.example.com\n// Social networks\ndomain.com test.com // personal domains";
  o.depends("user_domain_list_type", "text");
  o.rows = 8;
  o.rmempty = false;
  o.validate = function (section_id, value) {
    // Optional
    if (!value || value.length === 0) {
      return true;
    }

    const domains = main.parseValueList(value);

    if (!domains.length) {
      return _(
        "At least one valid domain must be specified. Comments-only content is not allowed.",
      );
    }

    const { valid, results } = main.bulkValidate(domains, (row) =>
      main.validateDomain(row, true),
    );

    if (!valid) {
      const errors = results
        .filter((validation) => !validation.valid) // Leave only failed validations
        .map((validation) => `${validation.value}: ${validation.message}`); // Collect validation errors

      return [_("Validation errors:"), ...errors].join("\n");
    }

    return true;
  };

  o = section.taboption(
    "lists",
    form.ListValue,
    "user_subnet_list_type",
    _("User Subnet List Type"),
    _("Select the list type for adding custom subnets"),
  );
  o.value("disabled", _("Disabled"));
  o.value("dynamic", _("Dynamic List"));
  o.value("text", _("Text List"));
  o.default = "disabled";
  o.rmempty = false;

  o = section.taboption(
    "lists",
    form.DynamicList,
    "user_subnets",
    _("User Subnets"),
    _(
      "Enter subnets in CIDR notation (e.g. 103.21.244.0/22) or single IP addresses",
    ),
  );
  o.placeholder = "IP or subnet";
  o.depends("user_subnet_list_type", "dynamic");
  o.rmempty = false;
  o.validate = function (section_id, value) {
    // Optional
    if (!value || value.length === 0) {
      return true;
    }

    const validation = main.validateSubnet(value);

    if (validation.valid) {
      return true;
    }

    return validation.message;
  };

  o = section.taboption(
    "lists",
    form.TextValue,
    "user_subnets_text",
    _("User Subnets List"),
    _(
      "Enter subnets in CIDR notation or single IP addresses, separated by commas, spaces, or newlines. You can add comments using //",
    ),
  );
  o.placeholder =
    "103.21.244.0/22\n// Google DNS\n8.8.8.8\n1.1.1.1/32, 9.9.9.9 // Cloudflare and Quad9";
  o.depends("user_subnet_list_type", "text");
  o.rows = 10;
  o.rmempty = false;
  o.validate = function (section_id, value) {
    // Optional
    if (!value || value.length === 0) {
      return true;
    }

    const subnets = main.parseValueList(value);

    if (!subnets.length) {
      return _(
        "At least one valid subnet or IP must be specified. Comments-only content is not allowed.",
      );
    }

    const { valid, results } = main.bulkValidate(subnets, main.validateSubnet);

    if (!valid) {
      const errors = results
        .filter((validation) => !validation.valid) // Leave only failed validations
        .map((validation) => `${validation.value}: ${validation.message}`); // Collect validation errors

      return [_("Validation errors:"), ...errors].join("\n");
    }

    return true;
  };

  o = section.taboption(
    "lists",
    form.DynamicList,
    "local_domain_lists",
    _("Local Domain Lists"),
    _("Specify the path to the list file located on the router filesystem"),
  );
  o.placeholder = "/path/file.lst";
  o.rmempty = true;
  o.validate = function (section_id, value) {
    // Optional
    if (!value || value.length === 0) {
      return true;
    }

    const validation = main.validatePath(value);

    if (validation.valid) {
      return true;
    }

    return validation.message;
  };

  o = section.taboption(
    "lists",
    form.DynamicList,
    "local_subnet_lists",
    _("Local Subnet Lists"),
    _("Specify the path to the list file located on the router filesystem"),
  );
  o.placeholder = "/path/file.lst";
  o.rmempty = true;
  o.validate = function (section_id, value) {
    // Optional
    if (!value || value.length === 0) {
      return true;
    }

    const validation = main.validatePath(value);

    if (validation.valid) {
      return true;
    }

    return validation.message;
  };

  o = section.taboption(
    "lists",
    form.DynamicList,
    "remote_domain_lists",
    _("Remote Domain Lists"),
    _("Specify remote URLs to download and use domain lists"),
  );
  o.placeholder = "https://example.com/domains.srs";
  o.rmempty = true;
  o.validate = function (section_id, value) {
    // Optional
    if (!value || value.length === 0) {
      return true;
    }

    const validation = main.validateUrl(value);

    if (validation.valid) {
      return true;
    }

    return validation.message;
  };

  o = section.taboption(
    "lists",
    form.DynamicList,
    "remote_subnet_lists",
    _("Remote Subnet Lists"),
    _("Specify remote URLs to download and use subnet lists"),
  );
  o.placeholder = "https://example.com/subnets.srs";
  o.rmempty = true;
  o.validate = function (section_id, value) {
    // Optional
    if (!value || value.length === 0) {
      return true;
    }

    const validation = main.validateUrl(value);

    if (validation.valid) {
      return true;
    }

    return validation.message;
  };

  o = section.taboption(
    "advanced",
    form.DynamicList,
    "fully_routed_ips",
    _("Fully Routed IPs"),
    _(
      "Specify local IP addresses or subnets whose traffic will always be routed through the configured route",
    ),
  );
  o.placeholder = "192.168.1.2 or 192.168.1.0/24";
  o.rmempty = true;
  o.depends("connection_type", "outbound");
  o.validate = function (section_id, value) {
    // Optional
    if (!value || value.length === 0) {
      return true;
    }

    const validation = main.validateSubnet(value);

    if (validation.valid) {
      return true;
    }

    return validation.message;
  };

  o = section.taboption(
    "advanced",
    form.Flag,
    "resolve_real_ip_for_routing",
    _("Resolve real IP for routing"),
    _("Enable DNS resolve to get real IP when routing"),
  );
  o.default = "0";
  o.rmempty = false;
  o.depends("connection_type", "outbound");

  createSectionColumns(section);
}

const EntryPoint = {
  createSectionContent,
};

return baseclass.extend(EntryPoint);
