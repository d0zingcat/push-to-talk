import { environment, getPreferenceValues, showHUD, showToast, Toast } from "@raycast/api";
import { spawn } from "child_process";
import path from "path";

interface Preferences {
  targetInputSource: string;
  restoreDelay: string;
}

export default async function main() {
  const { targetInputSource, restoreDelay } = getPreferenceValues<Preferences>();
  const delayMs = parseInt(restoreDelay, 10) || 3000;

  const helperPath = path.join(environment.assetsPath, "doubao-ime-helper");

  // 以后台分离进程启动，TypeScript 进程退出后 Swift Helper 继续独立运行完整流程
  const child = spawn(helperPath, ["full-flow", "--target", targetInputSource, "--delay", String(delayMs)], {
    detached: true,
    stdio: "ignore",  // 全部 ignore，避免 pipe 断裂时 Swift 进程收到 SIGPIPE 被杀死
  });

  // 等 300ms：足够捕获"找不到输入法"或"无辅助功能权限"等立即失败的情况
  const earlyExitCode = await new Promise<number | null>((resolve) => {
    let settled = false;

    child.on("exit", (code) => {
      if (!settled) {
        settled = true;
        resolve(code);
      }
    });

    setTimeout(() => {
      if (!settled) {
        settled = true;
        resolve(null); // 仍在运行，视为正常
      }
    }, 300);
  });

  if (earlyExitCode === 3) {
    await showToast({
      style: Toast.Style.Failure,
      title: "缺少辅助功能权限",
      message: "请前往「系统设置 → 隐私与安全性 → 辅助功能」，为 Raycast 授权",
    });
    return;
  }

  if (earlyExitCode === 2) {
    await showToast({
      style: Toast.Style.Failure,
      title: "切换输入法失败",
      message: `未找到输入法「${targetInputSource}」，请在扩展偏好中确认名称`,
    });
    return;
  }

  if (earlyExitCode !== null && earlyExitCode !== 0) {
    await showToast({
      style: Toast.Style.Failure,
      title: "执行失败",
      message: `Helper 退出码: ${earlyExitCode}`,
    });
    return;
  }

  // Helper 仍在后台运行，解除父进程对它的引用，让它独立完成剩余工作
  child.unref();

  await showHUD("语音输入中…");
}
