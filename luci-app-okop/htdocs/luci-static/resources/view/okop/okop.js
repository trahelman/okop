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

// Dashboard content
"require view.okop.dashboard as dashboard";

// Diagnostic content
"require view.okop.diagnostic as diagnostic";

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
    // The order matters: the first proxy/VPN section whose lists match wins, so rows can be dragged.
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

    // LuCI only checks the name syntax. An existing name would merge the new section into that one
    // ("settings" would even turn the global settings into a section), and the names below give
    // sing-box tags that collide with okop's own (direct-out, service-mixed-in).
    const reservedSectionNames = [
      "settings",
      "direct",
      "service",
      "diagnostic",
      "dashboard",
    ];
    const addSection = sectionsSection.handleAdd;
    sectionsSection.handleAdd = function (ev, name) {
      let message = null;
      if (reservedSectionNames.includes(name)) {
        message = _("The name %s is reserved, choose another one").format(name);
      } else if (uci.get("okop", name)) {
        message = _("A section named %s already exists").format(name);
      }

      if (message) {
        ui.addNotification(null, E("p", {}, [message]), "warning");
        return Promise.resolve();
      }

      return addSection.apply(this, arguments);
    };

    // Render section content
    section.createSectionContent(sectionsSection);

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
