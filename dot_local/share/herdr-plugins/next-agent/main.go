// Command next-agent focuses the next or previous Herdr Agent in a configured semantic state.
package main

import (
	"bufio"
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/BurntSushi/toml"
)

const (
	displayOrder   = "display"
	waitingOrder   = "waiting"
	noMatchMessage = "No matching Agents"
	socketTimeout  = 5 * time.Second
)

var supportedStates = []string{"idle", "working", "blocked", "done", "unknown"}

type config struct {
	States []string `toml:"states"`
	Order  string   `toml:"order"`
}

type agent struct {
	PaneID         string `json:"pane_id"`
	AgentStatus    string `json:"agent_status"`
	Focused        bool   `json:"focused"`
	StateChangeSeq int64  `json:"state_change_seq"`
}

func loadConfig(dir string) (config, error) {
	cfg := config{States: []string{"blocked"}, Order: displayOrder}
	if dir == "" {
		return cfg, nil
	}

	path := filepath.Join(dir, "config.toml")
	text, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return cfg, nil
	}
	if err != nil {
		return cfg, fmt.Errorf("read Next Agent configuration %s: %w", path, err)
	}
	meta, err := toml.Decode(string(text), &cfg)
	if err != nil {
		return cfg, fmt.Errorf("read Next Agent configuration %s: %w", path, err)
	}

	if undecoded := meta.Undecoded(); len(undecoded) > 0 {
		keys := make([]string, len(undecoded))
		for i, key := range undecoded {
			keys[i] = key.String()
		}
		slices.Sort(keys)
		return cfg, fmt.Errorf("invalid configuration: unknown field %s", strings.Join(keys, ", "))
	}
	if cfg.Order != displayOrder && cfg.Order != waitingOrder {
		return cfg, errors.New(`invalid configuration: order must be "display" or "waiting"`)
	}
	if len(cfg.States) == 0 {
		return cfg, errors.New("invalid configuration: states must contain at least one Agent state")
	}
	seen := make(map[string]bool, len(cfg.States))
	for _, state := range cfg.States {
		if seen[state] {
			return cfg, errors.New("invalid configuration: duplicate state")
		}
		seen[state] = true
		if !slices.Contains(supportedStates, state) {
			return cfg, fmt.Errorf("invalid configuration: unsupported state %s", state)
		}
	}
	return cfg, nil
}

// callHerdr sends one request over the Herdr API socket and decodes its result into out.
func callHerdr(socketPath, method string, params, out any) error {
	conn, err := net.DialTimeout("unix", socketPath, socketTimeout)
	if err != nil {
		return fmt.Errorf("herdr %s failed: %w", method, err)
	}
	defer conn.Close()
	if err := conn.SetDeadline(time.Now().Add(socketTimeout)); err != nil {
		return fmt.Errorf("herdr %s failed: %w", method, err)
	}

	request, err := json.Marshal(map[string]any{"id": "next-agent", "method": method, "params": params})
	if err != nil {
		return fmt.Errorf("herdr %s failed: %w", method, err)
	}
	if _, err := conn.Write(append(request, '\n')); err != nil {
		return fmt.Errorf("herdr %s failed: %w", method, err)
	}
	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil && !(errors.Is(err, io.EOF) && len(line) > 0) {
		return fmt.Errorf("herdr %s failed: %w", method, err)
	}

	var response struct {
		Result json.RawMessage `json:"result"`
		Error  *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(line, &response); err != nil {
		return fmt.Errorf("herdr %s returned an invalid response", method)
	}
	if response.Error != nil {
		return fmt.Errorf("herdr %s failed: %s", method, response.Error.Message)
	}
	if len(response.Result) == 0 || string(response.Result) == "null" {
		return fmt.Errorf("herdr %s returned an invalid response", method)
	}
	if out == nil {
		return nil
	}
	if err := json.Unmarshal(response.Result, out); err != nil {
		return fmt.Errorf("herdr %s returned an invalid response", method)
	}
	return nil
}

func listAgents(socketPath string) ([]agent, error) {
	var result struct {
		Agents []agent `json:"agents"`
	}
	if err := callHerdr(socketPath, "agent.list", struct{}{}, &result); err != nil {
		return nil, err
	}
	if result.Agents == nil {
		return nil, errors.New("herdr agent.list returned an invalid response")
	}
	return result.Agents, nil
}

// selectAgent picks the neighboring matching Agent, wrapping at either end.
func selectAgent(agents []agent, cfg config, step int) *agent {
	matches := func(a agent) bool { return slices.Contains(cfg.States, a.AgentStatus) }

	if cfg.Order == waitingOrder {
		var candidates []agent
		for _, a := range agents {
			if matches(a) {
				candidates = append(candidates, a)
			}
		}
		if len(candidates) == 0 {
			return nil
		}
		slices.SortStableFunc(candidates, func(a, b agent) int {
			return cmp.Compare(a.StateChangeSeq, b.StateChangeSeq)
		})
		current := focusedIndex(candidates)
		if current < 0 && step < 0 {
			current = 0
		}
		return &candidates[wrap(current+step, len(candidates))]
	}

	// Display order walks every Agent so the focused position anchors the search
	// even when the focused Agent itself does not match the configured states.
	current := focusedIndex(agents)
	if current < 0 && step < 0 {
		current = 0
	}
	for offset := 1; offset <= len(agents); offset++ {
		candidate := &agents[wrap(current+step*offset, len(agents))]
		if matches(*candidate) {
			return candidate
		}
	}
	return nil
}

func focusedIndex(agents []agent) int {
	return slices.IndexFunc(agents, func(a agent) bool { return a.Focused })
}

func wrap(i, n int) int {
	return (i%n + n) % n
}

func parseStep(args []string) (int, error) {
	switch {
	case len(args) == 0, len(args) == 1 && args[0] == "next":
		return 1, nil
	case len(args) == 1 && args[0] == "previous":
		return -1, nil
	}
	return 0, errors.New("usage: next-agent [next|previous]")
}

func run(args []string) error {
	step, err := parseStep(args)
	if err != nil {
		return err
	}
	cfg, err := loadConfig(os.Getenv("HERDR_PLUGIN_CONFIG_DIR"))
	if err != nil {
		return err
	}
	socketPath := os.Getenv("HERDR_SOCKET_PATH")
	if socketPath == "" {
		return errors.New("HERDR_SOCKET_PATH is not set")
	}
	agents, err := listAgents(socketPath)
	if err != nil {
		return err
	}
	target := selectAgent(agents, cfg, step)
	if target == nil {
		return callHerdr(socketPath, "notification.show", map[string]string{"title": noMatchMessage}, nil)
	}
	return callHerdr(socketPath, "agent.focus", map[string]string{"target": target.PaneID}, nil)
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
