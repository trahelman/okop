"use strict";
"require form";
"require baseclass";
"require ui";
"require uci";
"require tools.widgets as widgets";
"require view.okop.main as main";

const GROUP_TYPES = ["fallback", "urltest", "selector"];

function toArray(value) {
  if (value == null || value === "") {
    return [];
  }

  return Array.isArray(value) ? value : [value];
}

function connectionNames() {
  return uci.sections("okop", "outbound").map((section) => section[".name"]);
}

function typeLabel(type) {
  switch (type) {
    case "url":
      return _("Proxy link");
    case "json":
      return _("sing-box JSON");
    case "interface":
      return _("Network interface");
    case "fallback":
      return _("Fallback group");
    case "urltest":
      return _("Fastest of a group");
    case "selector":
      return _("Manual choice of a group");
    default:
      return _("not configured");
  }
}

// Short description of a proxy link: protocol and server name, never credentials
function describeProxyLink(link) {
  const match = String(link || "")
    .trim()
    .match(/^([a-z0-9]+):\/\/([^?#]*)[^#]*(?:#(.*))?$/i);
  if (!match) {
    return _("invalid link");
  }

  const [, scheme, authority, name] = match;
  // The server follows the last "@": a password may itself contain "/" or "@". Without "@" an ss link
  // is entirely base64 with the password inside, so nothing of it is shown.
  const at = authority.lastIndexOf("@");
  let label = "";
  if (at >= 0) {
    label = authority.slice(at + 1).split("/")[0];
  } else if (scheme.toLowerCase() !== "ss") {
    label = authority.split("/")[0];
  }
  if (name) {
    try {
      label = decodeURIComponent(name);
    } catch (e) {
      label = name;
    }
  }

  return label ? `${scheme.toLowerCase()} · ${label}` : scheme.toLowerCase();
}

function describeOutboundJson(json) {
  try {
    const outbound = JSON.parse(json);
    const server = outbound.server
      ? ` · ${outbound.server}${outbound.server_port ? ":" + outbound.server_port : ""}`
      : "";
    return `${outbound.type || "outbound"}${server}`;
  } catch (e) {
    return _("invalid JSON");
  }
}

// One line about a connection, for the tables of sections and connections
function describeConnection(name) {
  const get = (option) => uci.get("okop", name, option);

  if (!uci.get("okop", name)) {
    return _("connection %s does not exist").format(name);
  }

  switch (get("type")) {
    case "url":
      return describeProxyLink(get("url"));
    case "json":
      return describeOutboundJson(get("json"));
    case "interface":
      return `VPN · ${get("interface") || _("no interface")}`;
    case "fallback":
    case "urltest":
    case "selector":
      return `${typeLabel(get("type"))}: ${toArray(get("members")).join(" → ")}`;
    default:
      return _("not configured");
  }
}

// What refers to a connection: sections, groups and the list download setting
function connectionUsers(name) {
  const users = [];

  uci.sections("okop", "section").forEach((section) => {
    if (section.connection_type === "outbound" && section.outbound === name) {
      users.push(_("section %s").format(section[".name"]));
    }
  });

  uci.sections("okop", "outbound").forEach((outbound) => {
    if (toArray(outbound.members).includes(name)) {
      users.push(_("group %s").format(outbound[".name"]));
    }
  });

  if (
    uci.get("okop", "settings", "download_lists_via_proxy") === "1" &&
    uci.get("okop", "settings", "download_lists_via_outbound") === name
  ) {
    users.push(_("list downloads"));
  }

  return users;
}

// A member list that leads back to the group itself would make sing-box reject the configuration
function findCycle(name, members) {
  const visit = (current, path) => {
    if (path.includes(current)) {
      return [...path, current];
    }

    const currentMembers =
      current === name ? members : toArray(uci.get("okop", current, "members"));
    for (const member of currentMembers) {
      const cycle = visit(member, [...path, current]);
      if (cycle) {
        return cycle;
      }
    }

    return null;
  };

  return visit(name, []);
}

function lines(values) {
  // Arrays, not strings: LuCI inserts a string child as HTML, and these come from user input
  return E("div", {}, values.map((value) => E("div", {}, [value])));
}

function createOutboundColumns(section) {
  section.children.forEach((option) => {
    option.modalonly = true;
  });

  let o = section.option(form.DummyValue, "_kind", _("Type"));
  o.modalonly = false;
  o.textvalue = (section_id) => {
    const values = [typeLabel(uci.get("okop", section_id, "type"))];
    const description = describeConnection(section_id);
    if (!GROUP_TYPES.includes(uci.get("okop", section_id, "type"))) {
      values.push(description);
    } else {
      values.push(toArray(uci.get("okop", section_id, "members")).join(" → "));
    }
    if (uci.get("okop", section_id, "mixed_proxy_enabled") === "1") {
      values.push(
        _("mixed proxy on port %s").format(
          uci.get("okop", section_id, "mixed_proxy_port"),
        ),
      );
    }
    return lines(values);
  };

  o = section.option(form.DummyValue, "_users", _("Used by"));
  o.modalonly = false;
  o.textvalue = (section_id) => {
    const users = connectionUsers(section_id);
    return users.length ? lines(users) : E("em", {}, _("not used"));
  };
}

function createOutboundContent(section) {
  let o = section.option(
    form.ListValue,
    "type",
    _("Connection Type"),
    _(
      "A group combines other connections: fallback uses the first one that responds, fastest picks by latency, manual choice is switched on the dashboard",
    ),
  );
  ["url", "json", "interface", "fallback", "urltest", "selector"].forEach(
    (type) => o.value(type, typeLabel(type)),
  );
  o.default = "url";
  o.rmempty = false;

  o = section.option(
    form.TextValue,
    "url",
    _("Proxy Configuration URL"),
    _("vless://, ss://, trojan://, socks4/5://, hy2/hysteria2:// links"),
  );
  o.depends("type", "url");
  o.rows = 4;
  o.wrap = "soft";
  o.rmempty = false;
  o.validate = function (section_id, value) {
    if (!value) {
      return _("Enter a proxy link");
    }

    const validation = main.validateProxyUrl(value);
    return validation.valid ? true : validation.message;
  };

  o = section.option(
    form.Flag,
    "udp_over_tcp",
    _("UDP over TCP"),
    _("Applicable for SOCKS and Shadowsocks proxy"),
  );
  o.default = "0";
  o.depends("type", "url");

  o = section.option(
    form.TextValue,
    "json",
    _("Outbound Configuration"),
    _("Enter complete outbound configuration in JSON format"),
  );
  o.depends("type", "json");
  o.rows = 10;
  o.rmempty = false;
  o.validate = function (section_id, value) {
    if (!value) {
      return _("Enter the outbound configuration");
    }

    const validation = main.validateOutboundJson(value);
    return validation.valid ? true : validation.message;
  };

  o = section.option(
    widgets.DeviceSelect,
    "interface",
    _("Network Interface"),
    _("Select network interface for VPN connection"),
  );
  o.depends("type", "interface");
  o.noaliases = true;
  o.nobridges = false;
  o.noinactive = false;
  o.rmempty = false;
  o.filter = function (section_id, value) {
    // Interfaces of the router itself are never a VPN
    const blockedInterfaces = [
      "br-lan",
      "eth0",
      "eth1",
      "wan",
      "phy0-ap0",
      "phy1-ap0",
      "pppoe-wan",
      "lan",
    ];
    if (blockedInterfaces.includes(value)) {
      return false;
    }

    const device = this.devices.find((dev) => dev.getName() === value);
    if (!device) {
      return true;
    }

    const type = device.getType();
    return !(type === "wifi" || type === "wireless" || type.includes("wlan"));
  };

  o = section.option(
    form.Flag,
    "domain_resolver_enabled",
    _("Domain Resolver"),
    _(
      "Resolve domains sent through this connection with a DNS server reached through the connection itself",
    ),
  );
  o.default = "0";
  o.depends("type", "interface");

  o = section.option(
    form.ListValue,
    "domain_resolver_dns_type",
    _("DNS Protocol Type"),
    _("Select the DNS protocol type for the domain resolver"),
  );
  o.value("doh", _("DNS over HTTPS (DoH)"));
  o.value("dot", _("DNS over TLS (DoT)"));
  o.value("udp", _("UDP (Unprotected DNS)"));
  o.default = "udp";
  o.depends("domain_resolver_enabled", "1");

  o = section.option(
    form.Value,
    "domain_resolver_dns_server",
    _("DNS Server"),
    _("Select or enter DNS server address"),
  );
  Object.entries(main.DNS_SERVER_OPTIONS).forEach(([key, label]) => {
    o.value(key, _(label));
  });
  o.default = "8.8.8.8";
  o.depends("domain_resolver_enabled", "1");
  o.validate = function (section_id, value) {
    const validation = main.validateDNS(value);
    return validation.valid ? true : validation.message;
  };

  o = section.option(
    form.DynamicList,
    "members",
    _("Members"),
    _(
      "Connections of the group. For a fallback group the order is the priority: the first one that responds is used",
    ),
  );
  GROUP_TYPES.forEach((type) => o.depends("type", type));
  o.rmempty = false;
  // The other connections are offered, read when the form loads: connections added in the same
  // session are there too
  o.load = function (section_id) {
    this.keylist = [];
    this.vallist = [];
    connectionNames()
      .filter((name) => name !== section_id)
      .forEach((name) => this.value(name, name));
    return form.DynamicList.prototype.load.apply(this, arguments);
  };
  o.validate = function (section_id, value) {
    if (!value) {
      return true;
    }
    if (value === section_id) {
      return _("A group cannot contain itself");
    }
    if (uci.get("okop", value) !== "outbound") {
      return _("Connection %s does not exist").format(value);
    }

    // A cycle is only visible with the whole member list
    const cycle = findCycle(section_id, toArray(this.formvalue(section_id)));
    if (cycle) {
      return _("Groups contain each other: %s").format(cycle.join(" → "));
    }

    return true;
  };

  o = section.option(
    form.ListValue,
    "check_interval",
    _("Check Interval"),
    _("How often the members are checked"),
  );
  ["10s", "15s", "30s", "1m", "3m", "5m"].forEach((value) =>
    o.value(value, value),
  );
  o.depends("type", "fallback");
  o.depends("type", "urltest");
  // A fallback group should notice a failure quickly, the fastest member can be picked less often
  o.cfgvalue = function (section_id) {
    return (
      uci.get("okop", section_id, "check_interval") ||
      (uci.get("okop", section_id, "type") === "urltest" ? "3m" : "15s")
    );
  };

  o = section.option(
    form.Value,
    "check_url",
    _("Check URL"),
    _("The URL used to test server connectivity"),
  );
  o.value(
    "https://www.gstatic.com/generate_204",
    "https://www.gstatic.com/generate_204 (Google)",
  );
  o.value(
    "https://cp.cloudflare.com/generate_204",
    "https://cp.cloudflare.com/generate_204 (Cloudflare)",
  );
  o.value("https://captive.apple.com", "https://captive.apple.com (Apple)");
  o.default = "https://www.gstatic.com/generate_204";
  o.depends("type", "fallback");
  o.depends("type", "urltest");
  o.validate = function (section_id, value) {
    if (!value) {
      return true;
    }

    const validation = main.validateUrl(value);
    return validation.valid ? true : validation.message;
  };

  o = section.option(
    form.Value,
    "tolerance",
    _("URLTest Tolerance"),
    _(
      "The maximum difference in response times (ms) allowed when comparing servers",
    ),
  );
  o.default = "50";
  o.datatype = "range(50,1000)";
  o.depends("type", "urltest");

  o = section.option(
    form.Flag,
    "mixed_proxy_enabled",
    _("Enable Mixed Proxy"),
    _(
      "An HTTP and SOCKS proxy on the router that sends everything it receives through this connection",
    ),
  );
  o.default = "0";

  o = section.option(
    form.Value,
    "mixed_proxy_port",
    _("Mixed Proxy Port"),
    _(
      "Specify the port number on which the mixed proxy will run for this connection. Make sure the selected port is not used by another service",
    ),
  );
  o.rmempty = false;
  // Without this a typo is saved and okop then aborts the start
  o.datatype = "port";
  o.depends("mixed_proxy_enabled", "1");
  // The mixed proxy listens on the LAN address, where these ports are taken by the router itself.
  // sing-box would fail to bind and the start would be rolled back.
  o.validate = function (section_id, value) {
    const port = parseInt(value, 10);
    const routerPorts = [22, 53, 80, 443, 9090];
    if (routerPorts.includes(port)) {
      return _(
        "Port %d is used by the router itself (SSH, DNS, web interface or Clash API)",
      ).format(port);
    }

    const takenByOther = uci
      .sections("okop", "outbound")
      .some(
        (other) =>
          other[".name"] !== section_id &&
          other.mixed_proxy_enabled === "1" &&
          parseInt(other.mixed_proxy_port, 10) === port,
      );
    if (takenByOther) {
      return _("Port %d is already used by another connection").format(port);
    }

    return true;
  };

  createOutboundColumns(section);
}

// The connection a section routes through, chosen from the connections
function addConnectionOption(section, tab, name, title, description) {
  const o = section.taboption(tab, form.ListValue, name, title, description);
  o.load = function (section_id) {
    this.keylist = [];
    this.vallist = [];
    connectionNames().forEach((connection) =>
      this.value(connection, `${connection} (${describeConnection(connection)})`),
    );
    return form.ListValue.prototype.load.apply(this, arguments);
  };
  return o;
}

const EntryPoint = {
  createOutboundContent,
  addConnectionOption,
  connectionNames,
  connectionUsers,
  describeConnection,
  findCycle,
  toArray,
};

return baseclass.extend(EntryPoint);
