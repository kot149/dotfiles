// ctrl+c interrupts the session while it is running and otherwise falls through to
// the default bindings (prompt.clear, then app.exit). Bound above the built-in layers
// because session.interrupt consumes the key whenever a session is open, even idle.

export default {
  id: "ctrl-c-interrupt",
  setup(ctx: any) {
    ctx.keymap.layer(() => ({
      priority: 100,
      commands: [
        {
          bind: "ctrl+c",
          title: "Interrupt running session",
          group: "Session",
          run() {
            const route = ctx.ui.router.current()
            if (route?.type !== "session") return false
            if (ctx.data.session.status(route.sessionID) !== "running") return false
            ctx.keymap.dispatch("session.interrupt")
          },
        },
      ],
    }))
  },
}
