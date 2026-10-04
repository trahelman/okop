import { COMMAND_TIMEOUT } from '../constants';
import { withTimeout } from './withTimeout';

interface ExecuteShellCommandParams {
  command: string;
  args: string[];
  timeout?: number;
}

interface ExecuteShellCommandResponse {
  stdout: string;
  stderr: string;
  code?: number;
}

export async function executeShellCommand({
  command,
  args,
  timeout = COMMAND_TIMEOUT,
}: ExecuteShellCommandParams): Promise<ExecuteShellCommandResponse> {
  // Awaited, so that a timeout or an rpc error ends up in the catch: callers expect a result, not a throw
  try {
    return await withTimeout(
      fs.exec(command, args),
      timeout,
      [command, ...args].join(' '),
    );
  } catch (err) {
    const error = err as Error;

    return { stdout: '', stderr: error?.message, code: 0 };
  }
}
