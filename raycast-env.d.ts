/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {
  /** 目标输入法名称 - 豆包输入法的本地化显示名称（在系统「输入法」列表中看到的名称） */
  "targetInputSource": string,
  /** 恢复延迟（毫秒） - 触发语音输入后，等待多少毫秒再恢复原输入法 */
  "restoreDelay": string
}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `trigger` command */
  export type Trigger = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `trigger` command */
  export type Trigger = {}
}

