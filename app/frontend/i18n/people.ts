import type { UserCard } from "../api/types.ts"
import { t } from "./index.ts"

// A user's name where no avatar carries the agent marker: in choices, hidden
// text and tooltips (spec web-client, "Agent marker"). An agent is named as
// one, and a deleted agent as deleted, in words rather than by colour.
export function personName(user: Pick<UserCard, "name"> & Partial<Pick<UserCard, "agent" | "deleted">>): string {
  if (!user.agent) return user.name
  return t(user.deleted ? "agents.nameDeleted" : "agents.nameMarked", { name: user.name })
}
