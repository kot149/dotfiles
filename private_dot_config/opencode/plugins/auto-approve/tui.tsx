/**
 * auto-approve — the TUI half: a footer badge that reacts to gate decisions,
 * a `/auto-approve` slash command (alias `/aa`) for status, switching, judge
 * pinning, two-stage review, and a session panel listing the decision log,
 * plus toasts whenever the gate raises a call to the human.
 *
 * Our own implementation, against the published TUI plugin surface
 * (@opencode/plugin — keymap layers, slots, panels, toasts, RPC client).
 */
import { Plugin } from "@opencode/plugin/tui"
import {
  type CatalogModel,
  Gate,
  type GateDecision,
  type GateStatus,
  type ModelRef,
  type PinResult,
} from "./protocol.js"
import { createEffect, createSignal } from "solid-js"

const TONE: Record<string, string> = {
  allow: "green",
  block: "red",
  escalate: "yellow",
  unreachable: "yellow",
}

const GLYPH: Record<string, string> = { allow: "✓", block: "✗", escalate: "!", unreachable: "!" }

const PANEL_NAME = "auto-approve.log"

const clip = (text: string, max: number): string => (text.length > max ? `${text.slice(0, max - 1)}…` : text)

const fmtMs = (ms: number): string => (ms >= 1000 ? `${(ms / 1000).toFixed(1)}s` : `${ms}ms`)

/** `deepseek-v4/whatever` → `whatever`, so the badge stays short. */
const shortModel = (judge: ModelRef | null): string | null =>
  judge === null ? null : judge.id.split("/").pop() ?? judge.id

const HELP_TEXT = "usage: on | off | status | log | two | judge [provider/model] | judge2 [provider/model] | clear"

export default Plugin.define({
  id: "auto-approve",
  setup(context) {
    const rpcContext = context.client as {
      rpc: (contract: object) => {
        status(input?: object): Promise<GateStatus>
        toggle(input: { enabled?: boolean }): Promise<{ enabled: boolean }>
        setJudge(input: ModelRef): Promise<PinResult>
        setJudge2(input: ModelRef): Promise<PinResult>
        models(input?: object): Promise<{ models: CatalogModel[] }>
        configure(input: { twoStage?: boolean }): Promise<{ twoStage: boolean }>
        clear(input?: object): Promise<{ removed: number }>
        decisions(input?: { sessionID?: string; limit?: number }): Promise<{ decisions: GateDecision[] }>
        events: {
          on(name: "decision", handler: (entry: GateDecision) => void): () => void
          on(name: "config", handler: () => void): () => void
        }
      }
    }
    const rpc = rpcContext.rpc(Gate)

    const [state, setState] = createSignal<GateStatus>()
    const [flash, setFlash] = createSignal<{ line: string; tone: string } | undefined>(undefined)
    let flashTimer: ReturnType<typeof setTimeout> | undefined

    const toast = (message: string, variant: "info" | "success" | "warning" | "error" = "info"): void => {
      try {
        context.ui.toast.show({ title: "auto-approve", message, variant, duration: 4000 })
      } catch {
        // The toast surface is optional; never break a command over it.
      }
    }

    const refreshStatus = async (): Promise<void> => {
      try {
        setState(await rpc.status({}))
      } catch {
        // The server gate is not up yet; the badge simply stays hidden.
      }
    }

    const toggle = async (enabled?: boolean): Promise<void> => {
      const next = await rpc.toggle(enabled === undefined ? {} : { enabled })
      void refreshStatus()
      toast(`gate ${next.enabled ? "on" : "off"}`, next.enabled ? "success" : "info")
    }

    /** Opens a searchable model list; resolves to `provider/model`, or undefined on cancel. */
    const pickModel = async (slot: "judge" | "judge2"): Promise<string | undefined> => {
      const { models } = await rpc.models({})
      if (models.length === 0) {
        toast("no models in the catalog; pass <provider/model> instead", "warning")
        return undefined
      }
      const current = state()?.[slot]
      return context.ui.dialog.select({
        title: `auto-approve: ${slot} model`,
        placeholder: "Search",
        current: current == null ? undefined : `${current.providerID}/${current.id}`,
        options: models.map((model) => ({
          title: model.name,
          value: `${model.providerID}/${model.id}`,
          category: model.providerID,
          searchText: `${model.providerID}/${model.id}`,
        })),
      })
    }

    const pin = async (slot: "judge" | "judge2", typed?: string): Promise<void> => {
      const raw = typed === undefined || typed === "" ? await pickModel(slot) : typed
      if (raw === undefined) return
      const at = raw.indexOf("/")
      const providerID = at > 0 ? raw.slice(0, at) : ""
      const id = at > 0 ? raw.slice(at + 1) : ""
      if (providerID === "" || id === "") {
        toast(`${HELP_TEXT}`, "warning")
        return
      }
      const result = await (slot === "judge" ? rpc.setJudge({ providerID, id }) : rpc.setJudge2({ providerID, id }))
      if (result.ok) {
        void refreshStatus()
        toast(`${slot} pinned to ${providerID}/${id}`, "success")
      } else {
        toast(`${slot} refused: ${result.message}`, "error")
      }
    }

    const runCommand = async (input?: string): Promise<void> => {
      const parts = (input ?? "").trim().split(/\s+/).filter((part) => part !== "")
      const head = (parts[0] ?? "").toLowerCase()
      try {
        if (head === "") return void toggle().catch(() => toast("the gate did not answer", "error"))
        if (head === "on" || head === "off") return void toggle(head === "on")
        if (head === "judge" || head === "judge2") {
          return void pin(head, parts.slice(1).join("")).catch((problem) =>
            toast(clip(problem instanceof Error ? problem.message : String(problem), 160), "error"),
          )
        }
        if (head === "two") {
          const next = await rpc.configure({ twoStage: !(state()?.twoStage ?? true) })
          void refreshStatus()
          return void toast(`two-stage review ${next.twoStage ? "on" : "off"}`)
        }
        if (head === "log") {
          if (context.ui.panel.current()?.name === PANEL_NAME) {
            context.ui.panel.close()
            return void toast("decision panel closed")
          }
          const opened = context.ui.panel.open(PANEL_NAME, { presentation: "panel" })
          return void toast(opened ? "decision panel opened" : "no session open — the panel lives inside a session")
        }
        if (head === "clear") {
          const removed = await rpc.clear({})
          return void toast(`${removed.removed} decision record(s) removed`)
        }
        const view = state() ?? ((setState(await rpc.status({})), state()))
        if (view === undefined) return void toast("status unavailable — the gate is not reachable", "error")
        const judge = shortModel(view.judge) ?? "session default"
        const judge2 = shortModel(view.judge2) ?? "stage 1"
        if (head === "status" || head === "") {
          return void toast(
            `on · judge ${judge} → ${judge2} · ${view.twoStage ? "two-stage" : "single-stage"} · subagents ${view.subagents} · escalate ${view.escalation.afterConsecutive}/${view.escalation.perTurn} · timeout ${fmtMs(view.timeoutMs)}`,
            view.enabled ? "success" : "info",
          )
        }
        toast(HELP_TEXT, "warning")
      } catch (problem) {
        toast(clip(problem instanceof Error ? problem.message : String(problem), 160), "error")
      }
    }

    const stopDecision = rpc.events.on("decision", (entry) => {
      setFlash({
        line: `🛡 ${entry.action} ${GLYPH[entry.verdict] ?? "?"} ${fmtMs(entry.ms)}${entry.reason === "" ? "" : ` — ${clip(entry.reason, 70)}`}`,
        tone: TONE[entry.verdict] ?? "white",
      })
      clearTimeout(flashTimer)
      flashTimer = setTimeout(() => setFlash(undefined), 4000)
      if (entry.verdict === "allow") return
      toast(
        `${entry.action} ${entry.verdict === "block" ? "blocked" : "needs your approval"}${entry.reason === "" ? "" : ` — ${clip(entry.reason, 120)}`}`,
        entry.verdict === "block" ? "warning" : "error",
      )
    })
    const stopConfig = rpc.events.on("config", () => void refreshStatus())
    void refreshStatus()

    const footer = () => {
      const view = state()
      if (view === undefined) return null
      const parts: unknown[] = []
      parts.push(
        <text fg={view.enabled ? undefined : "gray"}>
          {view.enabled ? `🛡 auto-approve · ${shortModel(view.judge) ?? "default model"}` : "🛡 auto-approve off"}
        </text>,
      )
      const moment = flash()
      if (moment !== undefined) parts.push(<text fg={moment.tone}>{moment.line}</text>)
      return <box>{parts}</box>
    }

    const decisionLog = (props: { sessionID: string }) => {
      const [entries, setEntries] = createSignal<GateDecision[]>([])
      createEffect(() => {
        void (async () => {
          try {
            setEntries((await rpc.decisions({ sessionID: props.sessionID, limit: 12 })).decisions)
          } catch {
            setEntries([])
          }
        })()
      })
      return (
        <box>
          <text fg="gray">{"┄ auto-approve decisions ┄"}</text>
          {entries().length === 0 ? (
            <text fg="gray">no decisions recorded for this session yet</text>
          ) : (
            entries().map((entry) => (
              <text fg={TONE[entry.verdict] ?? "white"}>
                {`${GLYPH[entry.verdict] ?? "?"} ${entry.action} ${entry.resources.map((r) => clip(r, 48)).join(" · ")} ${fmtMs(entry.ms)}${entry.reason === "" ? "" : ` — ${clip(entry.reason, 56)}`}`}
              </text>
            ))
          )}
        </box>
      )
    }

    const unsubscribeBadge = context.ui.slot({ append: "prompt.footer", render: () => footer() })
    const unsubscribePanel = context.ui.slot({
      append: "session.panel",
      render: (panel) => {
        const active = panel as { name?: string; sessionID?: string }
        return active.name === PANEL_NAME ? decisionLog({ sessionID: active.sessionID ?? "" }) : null
      },
    })

    context.keymap.layer(() => ({
      mode: "global",
      priority: 60,
      commands: [
        {
          id: "auto-approve.command",
          title: "auto-approve: gate status and controls",
          group: "auto-approve",
          slash: { name: "auto-approve", aliases: ["aa"], arguments: true },
          run: runCommand,
        },
      ],
    }))

    return () => {
      clearTimeout(flashTimer)
      stopDecision()
      stopConfig()
      unsubscribeBadge()
      unsubscribePanel()
    }
  },
})
