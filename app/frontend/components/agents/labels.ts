import type { ChannelChoice } from "../../api/agents.ts"
import { choiceOf } from "../../api/agents.ts"
import type { AgentChannel, ApiTokenAccess } from "../../api/types.ts"
import { t } from "../../i18n/index.ts"

export const accessLabel = (access: ApiTokenAccess) => t(access === "read" ? "apiTokens.read" : "apiTokens.readWrite")

export function channelLabel(choice: ChannelChoice): string {
  if (choice === "api") return t("agents.channelApi")
  return choice === "mcp" ? t("agents.channelMcp") : t("agents.channelBoth")
}

export const channelsLabel = (channels: AgentChannel[]) => channelLabel(choiceOf(channels))
