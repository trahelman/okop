import { OkopShellMethods } from '../methods';
import { store } from '../services';

export async function fetchServicesInfo() {
  const [okop, singbox] = await Promise.all([
    OkopShellMethods.getStatus(),
    OkopShellMethods.getSingBoxStatus(),
  ]);

  if (!okop.success || !singbox.success) {
    store.set({
      servicesInfoWidget: {
        loading: false,
        failed: true,
        data: { singbox: 0, okop: 0 },
      },
    });
  }

  if (okop.success && singbox.success) {
    store.set({
      servicesInfoWidget: {
        loading: false,
        failed: false,
        data: { singbox: singbox.data.running, okop: okop.data.enabled },
      },
    });
  }
}
