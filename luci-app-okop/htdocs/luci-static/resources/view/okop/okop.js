"use strict";
"require view";
"require form";
"require baseclass";
"require network";
"require uci";
"require ui";
"require view.okop.main as main";

// Settings content
"require view.okop.settings as settings";

// Sections content
"require view.okop.section as section";

// Connections content
"require view.okop.outbound as outbound";

// Dashboard content
"require view.okop.dashboard as dashboard";

// Diagnostic content
"require view.okop.diagnostic as diagnostic";

// LuCI only checks the name syntax. An existing name would merge the new section into that one
// ("settings" would even turn the global settings into a section): sections and connections share one
// namespace in /etc/config/okop. The names below give sing-box tags that collide with okop's own
// (direct-out, service-mixed-in).
const reservedNames = ["settings", "direct", "service", "diagnostic", "dashboard"];

// Why a name cannot be given to a section or a connection, or null
function nameError(name) {
  if (!/^[A-Za-z0-9_]+$/.test(name)) {
    return _("A name may contain only Latin letters, digits and _");
  }
  if (reservedNames.includes(name)) {
    return _("The name %s is reserved, choose another one").format(name);
  }
  if (uci.get("okop", name)) {
    return _("The name %s is already taken").format(name);
  }
  return null;
}

function refuseTakenNames(gridSection) {
  const add = gridSection.handleAdd;
  gridSection.handleAdd = function (ev, name) {
    // An invalid syntax is reported by LuCI itself
    const message = /^[A-Za-z0-9_]+$/.test(name) ? nameError(name) : null;

    if (message) {
      ui.addNotification(null, E("p", {}, [message]), "warning");
      return Promise.resolve();
    }

    return add.apply(this, arguments);
  };
}

// LuCI cannot rename a UCI section. The section is copied under the new name next to the old one, what
// refers to it is pointed at the new name, and the old one is removed; the change is applied with the
// other unsaved changes.
function addRenameAction(gridSection, updateReferences) {
  const renderRowActions = gridSection.renderRowActions;
  gridSection.renderRowActions = function (section_id) {
    const tdEl = renderRowActions.apply(this, arguments);
    const buttons = tdEl.lastElementChild;
    if (buttons) {
      buttons.insertBefore(
        E(
          "button",
          {
            class: "btn cbi-button cbi-button-neutral",
            title: _("Rename"),
            click: ui.createHandlerFn(this, "showRenameModal", section_id),
            disabled: this.map.readonly || null,
          },
          [_("Rename")],
        ),
        buttons.querySelector(".cbi-button-remove"),
      );
    }
    return tdEl;
  };

  gridSection.showRenameModal = function (section_id) {
    // The dialog is only hidden: a second Enter while the saves run would rename twice
    let started = false;
    const input = E("input", {
      class: "cbi-input-text",
      type: "text",
      value: section_id,
      keydown: (ev) => ev.key === "Enter" && rename(),
    });
    const error = E("div", { class: "cbi-value-description" });

    const rename = () => {
      if (started) {
        return;
      }
      const name = input.value.trim();
      if (name === section_id) {
        ui.hideModal();
        return;
      }

      const message = nameError(name);
      if (message) {
        error.replaceChildren(E("strong", {}, [message]));
        return;
      }

      started = true;
      ui.hideModal();
      return this.handleRename(section_id, name).catch((e) => {
        ui.addNotification(
          null,
          E("p", {}, [_("%s was not renamed: %s").format(section_id, e?.message ?? e)]),
          "danger",
        );
      });
    };

    ui.showModal(_("Rename %s").format(section_id), [
      E("p", {}, [_("New name")]),
      input,
      error,
      E("div", { class: "right" }, [
        E("button", { class: "btn cbi-button", click: ui.hideModal }, [_("Cancel")]),
        " ",
        E("button", { class: "btn cbi-button cbi-button-positive", click: rename }, [
          _("Rename"),
        ]),
      ]),
    ]);
    input.focus();
    input.select();
  };

  gridSection.handleRename = function (section_id, name) {
    const config = this.map.config;
    const siblings = uci
      .sections(config, this.sectiontype)
      .map((section) => section[".name"]);
    const position = siblings.indexOf(section_id);
    const next = siblings[position + 1];
    const previous = siblings[position - 1];

    // Pending form values are saved first: the copy is made from the saved values. The copy and the
    // removal are saved separately: LuCI drops the position of a copy (sections: their priority)
    // when the same save also removes a section.
    return this.map
      .save(null, true)
      .then(() => {
        uci.clone(config, this.sectiontype, section_id, true, name);
        updateReferences(section_id, name);
        return this.map.save(null, true);
      })
      .then(() => {
        uci.remove(config, section_id);
        return this.map.save(null, true);
      })
      .then(() => {
        // rpcd stores the new position but returns sections without it until Apply: shown here too
        if (next) {
          uci.move(config, name, next, false);
        } else if (previous) {
          uci.move(config, name, previous, true);
        }
        return this.map.reset();
      });
  };
}

// Sections, groups and the list download setting name connections
function renameConnectionReferences(oldName, newName) {
  uci.sections("okop", "section").forEach((section) => {
    if (section.outbound === oldName) {
      uci.set("okop", section[".name"], "outbound", newName);
    }
  });

  uci.sections("okop", "outbound").forEach((connection) => {
    const members = outbound.toArray(connection.members);
    if (members.includes(oldName)) {
      uci.set(
        "okop",
        connection[".name"],
        "members",
        members.map((member) => (member === oldName ? newName : member)),
      );
    }
  });

  if (uci.get("okop", "settings", "download_lists_via_outbound") === oldName) {
    uci.set("okop", "settings", "download_lists_via_outbound", newName);
  }
}

const EntryPoint = {
  async render() {
    main.injectGlobalStyles();

    const okopMap = new form.Map(
      "okop",
      _("Okop Settings"),
      _("Configuration for Okop service"),
    );
    // Enable tab views
    okopMap.tabbed = true;

    // Sections tab
    // Sections are listed in a table and edited in a modal, like network interfaces.
    // The order matters: the first section whose lists match wins, so rows can be dragged.
    const sectionsSection = okopMap.section(
      form.GridSection,
      "section",
      _("Sections"),
    );
    sectionsSection.anonymous = false;
    sectionsSection.addremove = true;
    sectionsSection.sortable = true;
    sectionsSection.nodescriptions = true;
    sectionsSection.modaltitle = (section_id) =>
      _("Section") + ": " + section_id;

    refuseTakenNames(sectionsSection);
    // Nothing refers to a section by name
    addRenameAction(sectionsSection, () => {});

    // Render section content
    section.createSectionContent(sectionsSection);

    // Connections tab: what sections send their traffic through
    const outboundsSection = okopMap.section(
      form.GridSection,
      "outbound",
      _("Outbound connections"),
    );
    outboundsSection.anonymous = false;
    outboundsSection.addremove = true;
    outboundsSection.sortable = true;
    outboundsSection.nodescriptions = true;
    outboundsSection.modaltitle = (section_id) =>
      _("Connection") + ": " + section_id;
    refuseTakenNames(outboundsSection);
    addRenameAction(outboundsSection, renameConnectionReferences);

    // A section or a group left with a reference to a removed connection would stop okop from starting
    const removeOutbound = outboundsSection.handleRemove;
    outboundsSection.handleRemove = function (section_id) {
      const users = outbound.connectionUsers(section_id);
      if (users.length) {
        ui.addNotification(
          null,
          E("p", {}, [
            _("The connection %s is used by: %s. Choose another connection there first.").format(
              section_id,
              users.join(", "),
            ),
          ]),
          "warning",
        );
        return Promise.resolve();
      }

      return removeOutbound.apply(this, arguments);
    };

    outbound.createOutboundContent(outboundsSection);

    // Settings tab
    const settingsSection = okopMap.section(
      form.TypedSection,
      "settings",
      _("Settings"),
    );
    settingsSection.anonymous = true;
    settingsSection.addremove = false;
    // Make it named [ config settings 'settings' ]
    settingsSection.cfgsections = function () {
      return ["settings"];
    };

    // Render settings content
    settings.createSettingsContent(settingsSection);

    // Diagnostic tab
    const diagnosticSection = okopMap.section(
      form.TypedSection,
      "diagnostic",
      _("Diagnostics"),
    );
    diagnosticSection.anonymous = true;
    diagnosticSection.addremove = false;
    diagnosticSection.cfgsections = function () {
      return ["diagnostic"];
    };

    // Render diagnostic content
    diagnostic.createDiagnosticContent(diagnosticSection);

    // Dashboard tab
    const dashboardSection = okopMap.section(
      form.TypedSection,
      "dashboard",
      _("Dashboard"),
    );
    dashboardSection.anonymous = true;
    dashboardSection.addremove = false;
    dashboardSection.cfgsections = function () {
      return ["dashboard"];
    };

    // Render dashboard content
    dashboard.createDashboardContent(dashboardSection);

    // Inject core service
    main.coreService();

    return okopMap.render();
  },
};

return view.extend(EntryPoint);
