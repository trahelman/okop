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

function refuseTakenNames(gridSection) {
  const add = gridSection.handleAdd;
  gridSection.handleAdd = function (ev, name) {
    let message = null;
    if (reservedNames.includes(name)) {
      message = _("The name %s is reserved, choose another one").format(name);
    } else if (uci.get("okop", name)) {
      message = _("The name %s is already taken").format(name);
    }

    if (message) {
      ui.addNotification(null, E("p", {}, [message]), "warning");
      return Promise.resolve();
    }

    return add.apply(this, arguments);
  };
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
