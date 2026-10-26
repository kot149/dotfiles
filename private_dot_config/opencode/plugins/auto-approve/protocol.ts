/**
 * Wire contract between the gate (server plugin) and the surfaces (TUI plugin).
 *
 * The TUI reads status and the decision log, flips the gate, pins judge
 * models, and refreshes from the `decision` and `config` events. Every change
 * goes through the global options file, which the gate re-reads before each
 * judged call, so nothing here needs a restart.
 *
 * Judge model pinning returns a discriminated union: either the stored
 * provider/model pair, or the refusal reason. Keeping the refusal inside the
 * method's own output shape avoids a separate error channel entirely.
 */
import { Rpc } from "@opencode/plugin/rpc"

/** A provider/model pair in the form the one-shot generate endpoint accepts. */
export interface ModelRef {
  readonly providerID: string
  readonly id: string
}

/** Effective configuration as seen by the gate. */
export interface GateStatus {
  readonly enabled: boolean
  /** null means the session's default model. */
  readonly judge: ModelRef | null
  /** null means stage 2 uses the same model as stage 1. */
  readonly judge2: ModelRef | null
  readonly twoStage: boolean
  readonly subagents: "ask" | "classify"
  readonly escalation: { readonly afterConsecutive: number; readonly perTurn: number }
  readonly timeoutMs: number
  readonly skippedActions: readonly string[]
}

/**
 * One judged call. `unreachable` means the judge could not be consulted and
 * the gate fell back to a human approval prompt instead.
 */
export interface GateDecision {
  readonly at: string
  readonly sessionID: string
  readonly action: string
  readonly resources: readonly string[]
  readonly verdict: "allow" | "block" | "escalate" | "unreachable"
  readonly reason: string
  readonly ms: number
}

/** Result of pinning a judge model through `setJudge` / `setJudge2`. */
export type PinResult =
  | { readonly ok: true; readonly providerID: string; readonly id: string }
  | { readonly ok: false; readonly tag: string; readonly message: string }

type Field = { readonly type: string; readonly [extra: string]: unknown }

type Obj = {
  readonly type: string
  readonly properties?: Record<string, Field | Obj>
  readonly required?: readonly string[]
  readonly additionalProperties?: boolean
  readonly [extra: string]: unknown
}

const model: Obj = {
  type: "object",
  properties: {
    providerID: { type: "string" },
    id: { type: "string" },
  },
  required: ["providerID", "id"],
  additionalProperties: false,
}

const decision: Obj = {
  type: "object",
  properties: {
    at: { type: "string" },
    sessionID: { type: "string" },
    action: { type: "string" },
    resources: { type: "array", items: { type: "string" } },
    verdict: { type: "string", enum: ["allow", "block", "escalate", "unreachable"] },
    reason: { type: "string" },
    ms: { type: "number" },
  },
  required: ["at", "sessionID", "action", "resources", "verdict", "reason", "ms"],
  additionalProperties: false,
}

const nothing: Obj = { type: "object", additionalProperties: false }

const status: Obj = {
  type: "object",
  properties: {
    enabled: { type: "boolean" },
    judge: { type: ["object", "null"], additionalProperties: true },
    judge2: { type: ["object", "null"], additionalProperties: true },
    twoStage: { type: "boolean" },
    subagents: { type: "string", enum: ["ask", "classify"] },
    escalation: {
      type: "object",
      properties: {
        afterConsecutive: { type: "number" },
        perTurn: { type: "number" },
      },
      required: ["afterConsecutive", "perTurn"],
      additionalProperties: false,
    },
    timeoutMs: { type: "number" },
    skippedActions: { type: "array", items: { type: "string" } },
  },
  required: ["enabled", "judge", "judge2", "twoStage", "subagents", "escalation", "timeoutMs", "skippedActions"],
  additionalProperties: false,
}

const toggleIn: Obj = {
  type: "object",
  properties: { enabled: { type: "boolean" } },
  additionalProperties: false,
}

const toggleOut: Obj = {
  type: "object",
  properties: { enabled: { type: "boolean" } },
  required: ["enabled"],
  additionalProperties: false,
}

const judgeOut: Obj = {
  type: "object",
  properties: {
    ok: { type: "boolean" },
    providerID: { type: "string" },
    id: { type: "string" },
    tag: { type: "string" },
    message: { type: "string" },
  },
  required: ["ok"],
  additionalProperties: true,
}

const decisionsIn: Obj = {
  type: "object",
  properties: {
    sessionID: { type: "string" },
    limit: { type: "number" },
  },
  additionalProperties: false,
}

const decisionsOut: Obj = {
  type: "object",
  properties: { decisions: { type: "array", items: decision } },
  required: ["decisions"],
  additionalProperties: false,
}

const clearOut: Obj = {
  type: "object",
  properties: { removed: { type: "number" } },
  required: ["removed"],
  additionalProperties: false,
}

const configureIn: Obj = {
  type: "object",
  properties: {
    twoStage: { type: "boolean" },
    subagents: { type: "string", enum: ["ask", "classify"] },
  },
  additionalProperties: false,
}

const configureOut: Obj = {
  type: "object",
  properties: {
    twoStage: { type: "boolean" },
    subagents: { type: "string", enum: ["ask", "classify"] },
  },
  required: ["twoStage", "subagents"],
  additionalProperties: false,
}

const configEvent: Obj = {
  type: "object",
  properties: {
    enabled: { type: "boolean" },
    twoStage: { type: "boolean" },
    judge: model,
    judge2: model,
  },
  required: ["enabled"],
  additionalProperties: false,
}

export const Gate = Rpc.define({
  id: "auto-approve",
  methods: {
    status: { input: nothing, output: status },
    toggle: { input: toggleIn, output: toggleOut },
    setJudge: { input: model, output: judgeOut },
    setJudge2: { input: model, output: judgeOut },
    configure: { input: configureIn, output: configureOut },
    decisions: { input: decisionsIn, output: decisionsOut },
    clear: { input: nothing, output: clearOut },
  },
  events: {
    decision: { schema: decision },
    config: { schema: configEvent },
  },
})
