// eslint-disable-next-line @typescript-eslint/no-namespace
export namespace ClashAPI {
  export interface ProxyHistoryEntry {
    time: string;
    delay: number;
  }

  export interface ProxyBase {
    type: string;
    name: string;
    udp: boolean;
    history: ProxyHistoryEntry[];
    now?: string;
    all?: string[];
  }

  export interface Proxies {
    proxies: Record<string, ProxyBase>;
  }
}

// eslint-disable-next-line @typescript-eslint/no-namespace
export namespace Okop {
  // Available commands:
  // start                   Start okop service
  // stop                    Stop okop service
  // reload                  Reload okop configuration
  // restart                 Restart okop service
  // enable                  Enable okop autostart
  // disable                 Disable okop autostart
  // main                    Run main okop process
  // list_update             Update domain lists
  // check_proxy             Check proxy connectivity
  // check_nft               Check NFT rules
  // check_nft_rules         Check NFT rules status
  // check_sing_box          Check sing-box installation and status
  // check_logs              Show okop logs from system journal
  // check_sing_box_logs     Show sing-box logs
  // check_fakeip            Test FakeIP on router
  // clash_api               Clash API interface for managing proxies and groups
  // show_config             Display current okop configuration
  // show_version            Show okop version
  // show_sing_box_config    Show sing-box configuration
  // show_sing_box_version   Show sing-box version
  // show_system_info        Show system information
  // get_status              Get okop service status
  // get_sing_box_status     Get sing-box service status
  // check_dns_available     Check DNS server availability
  // global_check            Run global system check

  export enum AvailableMethods {
    CHECK_DNS_AVAILABLE = 'check_dns_available',
    CHECK_FAKEIP = 'check_fakeip',
    CHECK_NFT_RULES = 'check_nft_rules',
    GET_STATUS = 'get_status',
    CHECK_SING_BOX = 'check_sing_box',
    GET_SING_BOX_STATUS = 'get_sing_box_status',
    GET_DNS_GUARD_STATUS = 'get_dns_guard_status',
    LIST_UPDATE_START = 'list_update_start',
    LIST_UPDATE_STATUS = 'list_update_status',
    CLASH_API = 'clash_api',
    RESTART = 'restart',
    START = 'start',
    STOP = 'stop',
    ENABLE = 'enable',
    DISABLE = 'disable',
    GLOBAL_CHECK = 'global_check',
    SHOW_SING_BOX_CONFIG = 'show_sing_box_config',
    CHECK_LOGS = 'check_logs',
    GET_SYSTEM_INFO = 'get_system_info',
  }

  export enum AvailableClashAPIMethods {
    GET_PROXIES = 'get_proxies',
    GET_PROXY_LATENCY = 'get_proxy_latency',
    GET_GROUP_LATENCY = 'get_group_latency',
    SET_GROUP_PROXY = 'set_group_proxy',
  }

  export interface Outbound {
    code: string;
    displayName: string;
    latency: number;
    type: string;
    selected: boolean;
    // A latency test on this page covered the outbound and it did not respond
    unreachable?: boolean;
  }

  export interface OutboundGroup {
    // A connection group: latency is tested for the whole group
    withTagSelect: boolean;
    // The member can be chosen by hand. A fallback group switches by itself.
    selectable?: boolean;
    code: string;
    displayName: string;
    outbounds: Outbound[];
  }

  export type ConnectionType =
    | 'url'
    | 'json'
    | 'interface'
    | 'fallback'
    | 'urltest'
    | 'selector';

  // A section of /etc/config/okop: the settings, a section with lists or a connection
  export interface ConfigSection {
    '.name': string;
    '.type': 'settings' | 'section' | 'outbound';
    yacd_secret_key?: string;
    connection_type?: 'outbound' | 'block' | 'exclusion';
    outbound?: string;
    type?: ConnectionType;
    url?: string;
    json?: string;
    interface?: string;
    members?: string | string[];
  }

  export interface MethodSuccessResponse<T> {
    success: true;
    data: T;
  }

  export interface MethodFailureResponse {
    success: false;
    error: string;
  }

  export type MethodResponse<T> =
    | MethodSuccessResponse<T>
    | MethodFailureResponse;

  export interface DnsCheckResult {
    dns_type: 'udp' | 'doh' | 'dot';
    dns_server: string;
    dns_status: 0 | 1;
    dns_on_router: 0 | 1;
    bootstrap_dns_server: string;
    bootstrap_dns_status: 0 | 1;
    dhcp_config_status: 0 | 1;
  }

  export interface NftRulesCheckResult {
    table_exist: 0 | 1;
    rules_mangle_exist: 0 | 1;
    rules_mangle_counters: 0 | 1;
    rules_mangle_output_exist: 0 | 1;
    rules_mangle_output_counters: 0 | 1;
    rules_proxy_exist: 0 | 1;
    rules_proxy_counters: 0 | 1;
    rules_other_mark_exist: 0 | 1;
  }

  export interface SingBoxCheckResult {
    sing_box_installed: 0 | 1;
    sing_box_version_ok: 0 | 1;
    sing_box_service_exist: 0 | 1;
    sing_box_autostart_disabled: 0 | 1;
    sing_box_process_running: 0 | 1;
    sing_box_ports_listening: 0 | 1;
  }

  export interface FakeIPCheckResult {
    fakeip: boolean;
    IP: string;
  }

  export interface GetStatus {
    enabled: number;
    status: string;
  }

  export type DnsGuardState =
    | 'ok'
    | 'sing_box_down'
    | 'dns_server_down'
    | 'stopped';

  export interface GetDnsGuardStatus {
    running: number;
    state: DnsGuardState;
    // Unix time of the last switch, 0 while the guard has not recorded it
    since: number;
    // 0 with "Dont Touch My DHCP!": the guard does not switch dnsmasq
    manage_dnsmasq: number;
  }

  export type ListUpdateState =
    | 'none'
    | 'running'
    | 'ok'
    | 'partial'
    | 'network'
    | 'interrupted';

  export interface GetListUpdateStatus {
    state: ListUpdateState;
    // Unix time, finished is 0 while the update runs
    started: number;
    finished: number;
    // With state "network": dns or github
    reason: string;
    // URLs that could not be downloaded
    failed: string[];
  }

  export interface ListUpdateStartResult {
    started: number;
    reason: '' | 'not_running' | 'already_running';
  }

  export interface GetSingBoxStatus {
    running: number;
    enabled: number;
    status: string;
  }

  export interface GetSystemInfo {
    okop_version: string;
    okop_latest_version: string;
    luci_app_version: string;
    sing_box_version: string;
    openwrt_version: string;
    device_model: string;
  }

  export interface GetClashApiProxyLatency {
    delay: number;
    message?: string;
  }

  export type GetClashApiGroupLatency = Record<string, number>;
}
