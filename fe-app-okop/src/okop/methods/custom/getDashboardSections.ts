import { getConfigSections } from './getConfigSections';
import { Okop } from '../../types';
import { getProxyUrlName } from '../../../helpers/getProxyUrlName';
import { OkopShellMethods } from '../shell';

interface IGetDashboardSectionsResponse {
  success: boolean;
  data: Okop.OutboundGroup[];
}

type ClashProxy = {
  code: string;
  value: {
    name?: string;
    type?: string;
    now?: string;
    all?: string[];
    history?: { delay?: number }[];
  };
};

const GROUP_TYPES: Okop.ConnectionType[] = ['fallback', 'urltest', 'selector'];

function toArray(value?: string | string[]): string[] {
  if (!value) {
    return [];
  }

  return Array.isArray(value) ? value : [value];
}

// The tag okop gives a connection in the sing-box configuration
function tagOf(name: string) {
  return `${name}-out`;
}

// The JSON may come from the uci CLI without validation, and a tag such as "50%" is not valid URI
// encoding. Either threw and left the whole dashboard without connections.
function getOutboundJsonTag(outboundJson?: string): string | undefined {
  let tag: unknown;
  try {
    tag = JSON.parse(outboundJson ?? '')?.tag;
  } catch {
    return undefined;
  }

  if (typeof tag !== 'string' || !tag) {
    return undefined;
  }

  try {
    return decodeURIComponent(tag);
  } catch {
    return tag;
  }
}

// What a connection is called on its card: the name of the link, the interface or the JSON tag
function describe(connection?: Okop.ConfigSection): string {
  if (!connection) {
    return '';
  }

  switch (connection.type) {
    case 'url':
      return getProxyUrlName(connection.url ?? '');
    case 'json':
      return getOutboundJsonTag(connection.json) ?? '';
    case 'interface':
      return connection.interface ?? '';
    default:
      return '';
  }
}

function toOutbound(
  code: string,
  displayName: string,
  proxy: ClashProxy | undefined,
  selected: boolean,
): Okop.Outbound {
  return {
    code,
    displayName,
    latency: proxy?.value?.history?.[0]?.delay || 0,
    type: proxy?.value?.type || '',
    selected,
  };
}

export async function getDashboardSections(): Promise<IGetDashboardSectionsResponse> {
  const configSections = await getConfigSections();
  const clashProxies = await OkopShellMethods.getClashApiProxies();

  if (!clashProxies.success) {
    return {
      success: false,
      data: [],
    };
  }

  const proxies: ClashProxy[] = Object.entries(clashProxies.data.proxies).map(
    ([key, value]) => ({ code: key, value: value as ClashProxy['value'] }),
  );
  const findProxy = (code: string) =>
    proxies.find((proxy) => proxy.code === code);

  const connections = configSections.filter(
    (section) => section['.type'] === 'outbound',
  );
  const findConnection = (name: string) =>
    connections.find((connection) => connection['.name'] === name);

  // A connection that is only a member of groups is shown inside them, not on a card of its own
  const usedBySection = new Set(
    configSections
      .filter(
        (section) =>
          section['.type'] === 'section' &&
          section.connection_type === 'outbound' &&
          section.outbound,
      )
      .map((section) => section.outbound as string),
  );
  const members = new Set(
    connections.flatMap((connection) => toArray(connection.members)),
  );

  const data = connections
    .filter(
      (connection) =>
        usedBySection.has(connection['.name']) ||
        !members.has(connection['.name']),
    )
    .map((connection): Okop.OutboundGroup => {
      const name = connection['.name'];
      const code = tagOf(name);
      const proxy = findProxy(code);

      if (!GROUP_TYPES.includes(connection.type as Okop.ConnectionType)) {
        return {
          withTagSelect: false,
          code,
          displayName: name,
          outbounds: [
            toOutbound(
              code,
              describe(connection) || proxy?.value?.name || name,
              proxy,
              true,
            ),
          ],
        };
      }

      const memberOutbounds = toArray(connection.members).map((member) => {
        const description = describe(findConnection(member));
        return toOutbound(
          tagOf(member),
          description && description !== member
            ? `${member} · ${description}`
            : member,
          findProxy(tagOf(member)),
          proxy?.value?.now === tagOf(member),
        );
      });

      if (connection.type === 'urltest') {
        // The group is a selector over the members and the URLTest that picks the fastest one
        const urltestCode = tagOf(`${name}-urltest`);
        memberOutbounds.unshift(
          toOutbound(
            urltestCode,
            _('Fastest'),
            findProxy(urltestCode),
            proxy?.value?.now === urltestCode,
          ),
        );
      }

      return {
        withTagSelect: true,
        selectable: connection.type !== 'fallback',
        code,
        displayName: name,
        outbounds: memberOutbounds,
      };
    });

  return {
    success: true,
    data,
  };
}
