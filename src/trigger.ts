import { environment, getPreferenceValues, showHUD, showToast, Toast } from "@raycast/api";
import { execFile } from "child_process";
import path from "path";

interface Preferences {
  targetInputSource: string;
  restoreDelay: string; // Raycast textfield 返回 string，需手动 parse
}

function runHelper(args: string[]): Promise<{ stdout: string; exitCode: number }> {
  const helperPath = path.join(environment.assetsPath, "doubao-ime-helper");
  return new Promise((resolve) => {
    execFile(helperPath, args, (error, stdout) => {
      resolve({
        stdout,
        exitCode: error ? (error.code ?? 1) : 0,
      });
    });
  });
}

export default async function main() {
  const { targetInputSource, restoreDelay } = getPreferenceValues<Preferences>();
  const delayMs = parseInt(restoreDelay, 10) || 3000;

  const { stdout, exitCode } = await runHelper(["switch-and-trigger", "--target", targetInputSource]);

  if (exitCode === 3) {
    await showToast({
      style: Toast.Style.Failure,
      title: "缺少辅助功能权限",
      message: "请前往「系统设置 → 隐私与安全性 → 辅助功能」，为 Raycast 授权",
    });
    return;
  }

  if (exitCode !== 0) {
    await showToast({
      style: Toast.Style.Failure,
      title: "切换输入法失败",
      message: `未找到输入法「${targetInputSource}」，请在扩展偏好中确认名称`,
    });
    return;
  }

  const previousSource = stdout.trim();

  await showHUD("语音输入中…");

  await new Promise<void>((resolve) => setTimeout(resolve, delayMs));

  await runHelper(["restore", "--target", previousSource]);
}
