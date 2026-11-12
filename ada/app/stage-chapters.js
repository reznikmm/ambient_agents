(() => {
// Ada adaptation of the ambient agents workshop. The browser renders these
// chapters; all agent, HTTP and protocol behavior lives in the Ada executable.
window.STAGE_AGENDA = [
  [0, 5, 'Signals and the workbench', 'talk'],
  [5, 15, 'Chat and GitHub input', 'live'],
  [15, 25, 'Noise, watches and duplicates', 'live'],
  [25, 35, 'Sessions, policy and approvals', 'live'],
  [35, 45, 'Timers and memory', 'live'],
  [45, 50, 'MCP and ACP', 'talk'],
  [50, 55, 'Checks and questions', 'talk'],
];
const code = (file, text) => ({ type: 'code', file, code: text });
const cards = (...items) => ({ type: 'cards', cols: 3, items: items.map(([h, html]) => ({ h, html })) });
const embed = (path, h = 'The stage agent') => ({ type: 'embed', h, src: path, full: path, height: 520 });
const load = (step) => ['load', `Load step-${step}`, step];
const storm = ['storm'];
const reset = ['reset'];
const trigger = (label, scenario) => ['trigger', label, scenario];
const chapters = [
  {
    id: 'title', part: 'Introduction', nav: 'Signals', step: null,
    title: 'Agents that work while you don’t — in Ada',
    lede: 'An Ada adaptation of Art Yavorsky’s ambient agents workshop: one conversation, GitHub signals, a clock, and six behavioral checks. The runtime uses the local MCP, ACP and Chat Completions libraries.',
    sections: [{ type: 'agenda' }, { type: 'lanes' }],
    points: ['A signal starts work without another prompt.', 'A watch says what matters. A policy protects your attention.', 'All demonstrations run without model credentials.'],
    actions: [['link', 'Compare agents', '/dashboard']],
    say: ['Open the dashboard and compare the naive and finished agents.', 'The fixture stays unchanged while the implementation moves from TypeScript to Ada.'],
  },
  {
    id: 'scaffold', part: 'Build', nav: 'Step 0 · scaffold', step: 0,
    title: 'The workbench before the agent',
    lede: 'The browser app, simulator and checks are ready. Step 0 records input but has no processing pipeline.',
    sections: [code('Terminal', 'make build\nmake eval\nmake start\n# naive :4101, finished :4102, stage :4103, dashboard :4000'),
      cards(['Build', 'Alire pins the three sibling libraries. GNAT compiles Ada 2022.'], ['State', 'Each running instance owns its state file and Markdown memory.'], ['Steps', 'Load selects behavior and resets state. It preserves source edits.'])],
    points: ['Use the prompt under ada/prompts/.', 'Run evaluations with the E control.', 'Step 0: 0/6.'],
    actions: [load(0), storm, reset], say: ['Nothing reaching a worker is not a passing evaluation.'],
  },
  {
    id: 'chat', part: 'Build', nav: 'Step 1 · chat', step: 1,
    title: 'A model, tools and an Ada loop',
    lede: 'Chat_Completions_API supplies typed messages and function calls. The runtime executes tools, returns their results, and calls the model again, up to ten turns.',
    sections: [embed('/chat?embed=1&instance=stage'), code('Ambient.Models · Complete', `Server.Set_Request_Handler (HTTP'Unchecked_Access);
Server.Set_URL (To_Virtual_String (URL));
Server.Set_API_Key (To_Virtual_String (Token));
Chat_Completions_API.Chats.Chat
  (Server, To_Virtual_String (Model), Messages,
   Tools => Tools, Response => Response, Success => Success);`),
      cards(['Tools', 'Checkout reads/search, GitHub reads, skills, watches, reminders and Markdown memory.'], ['Context', 'Trim at user boundaries so every tool call retains its result.'], ['Transport', 'OpenAI-compatible HTTP through the supplied library. NDJSON carries complete responses to the app.'])],
    points: ['Configure CHAT_COMPLETIONS_URL and CHAT_MODEL for chat.', 'Without credentials, simulation and evaluations remain available.', 'Step 1: 0/6.'],
    actions: [load(1), reset], say: ['Ask the agent to read its README.', 'A completion may request a tool rather than give an answer.'],
  },
  {
    id: 'github', part: 'Build', nav: 'Step 2 · GitHub', step: 2,
    title: 'Every source becomes one event shape',
    lede: 'Signed webhooks and polling normalize GitHub activity into Ambient.Types.Agent_Event. Polling records an initial baseline and shares IDs with webhooks.',
    sections: [code('Ambient.Sources · native HMAC-SHA256', `Context : GNAT.SHA256.Context :=
  GNAT.SHA256.HMAC_Initial_Context (Secret);
GNAT.SHA256.Update (Context, Body_Text);
-- Compare the complete expected signature before ingesting.`),
      code('Ambient.Types', `type Agent_Event is record
   Id, Source, Login, Subject, Title, Body_Text, URL, Watch : Text;
   Kind : Event_Kind := Issue_Opened;
   Bot : Boolean := False;
   At_Time : Long_Long_Integer := 0;
   Routing : Signal := Issues;
end record;`)],
    points: ['Set GITHUB_WEBHOOK_SECRET to test forged signatures.', 'The first poll does not replay existing history.', 'Step 2: 0/6.'],
    actions: [load(2), ['webhook', 'Signed issue', 'issue'], ['webhook', 'Forged signature', 'issue-bad'], ['webhook', 'CI failed', 'ci']],
    say: ['The signature covers the raw request bytes.', 'Input is recorded here; the processing pipeline arrives next.'],
  },
  {
    id: 'naive', part: 'Improve', nav: 'Step 3 · chaos', step: 3,
    title: 'Every event starts work',
    lede: 'Bots, edits, reactions and repeated deliveries all start a worker. The fixed 60-event storm makes the cost visible.',
    sections: [code('Ambient.Engine', 'Agent.Replay (Parse (Read_File ("fixtures/storm.json")));\nAgent.Flush;'),
      cards(['Noise', 'Bots and self posts create unnecessary turns.'], ['Duplicates', 'Seven deliveries of one CI problem start repeated work.'], ['Attention', 'Every result sends a notification.'])],
    points: ['Run the storm, then inspect the thread.', 'Run the six checks with E.', 'Step 3: 0/6.'],
    actions: [load(3), storm, reset], say: ['This is the baseline the remaining steps improve.'],
  },
  {
    id: 'gate', part: 'Improve', nav: 'Step 4 · filter and gate', step: 4,
    title: 'Ignore noise, then check the watches',
    lede: 'The prefilter drops known noise without a model. The gate ignores reactions, matches standing watches, and asks before destructive requests. Decision providers fall back to a model or rules.',
    sections: [code('Ambient.Engine · Ingest', `if Event.Bot then
   Reason := "bot";
elsif Event.Kind = Issue_Edited then
   Reason := "edit, not new work";
elsif Event.Kind = CI_Passed then
   Reason := "green build";
end if;`),
      cards(['Prefilter', 'Bots, edits, green CI and the agent’s own posts never reach a worker.'], ['Gate', 'Act, ignore or ask, with a reason and matching watch.'], ['Fallback', 'The rules path keeps the workshop usable without a provider.'])],
    points: ['Watches live in memory/watches.md.', 'The gate reads watches on each batch.', 'Step 4: 2/6.'],
    actions: [load(4), storm, trigger('+1 comment', 'reaction'), trigger('Other PR', 'pr-opened')],
    say: ['Compare gate calls, worker runs and ignored reasons.', 'The optional decision playground is available on /decisions.'],
  },
  {
    id: 'inbox', part: 'Improve', nav: 'Step 5 · coalesce', step: 5,
    title: 'Five alerts can be one problem',
    lede: 'The inbox remembers event IDs and the last handled time for each subject and kind. Reports on a subject update its existing thread entry.',
    sections: [code('Ambient.Engine · Offer', `Key : constant String :=
  To_UTF_8_String (Event.Subject) & "|" & Name (Event.Kind);
-- Merge a seen ID, or the same subject/kind within five minutes.
-- Otherwise record the delivery and run the subject's work.`)],
    points: ['The clock controls the five-minute quiet window.', 'New kinds on the same subject still carry new information.', 'Step 5: 3/6.'],
    actions: [load(5), trigger('CI fails', 'ci-failed'), ['clock', '+10 min', 10], storm],
    say: ['Press CI fails repeatedly; then advance the clock.'],
  },
  {
    id: 'policy', part: 'Improve', nav: 'Step 6 · sessions and policy', step: 6,
    title: 'Keep context, and ask when needed',
    lede: 'CI, issues and PRs keep separate sessions. Reversibility and confidence choose act, draft, ask or note. Daily notification budgets come from preferences.md.',
    sections: [code('Ambient.Engine · policy', `if Result.Reversible and Result.Confidence >= 0.7 then
   Route := "act";
   Ping := False;
elsif not Result.Reversible and Result.Confidence < 0.7 then
   Route := "note";
   Ping := False;
else
   Route := (if Result.Reversible then "draft" else "ask");
   Ping := True;
end if;`), embed('/chat?embed=1&instance=stage')],
    points: ['Add a “PRs about cats” watch before triggering the cat PR.', 'Yes/No answers resume the subject without another gate decision.', 'Step 6: 5/6.'],
    actions: [load(6), storm, trigger('Cat PR', 'cat-pr')],
    say: ['Open a pending approval in the main thread.', 'The runtime executes worker turns serially; external sessions retain context.'],
  },
  {
    id: 'timers', part: 'Improve', nav: 'Step 7 · come back later', step: 7,
    title: 'The agent books its own next signal',
    lede: 'A red CI result schedules a check-back. Due timers return through the event pipeline; personal reminders go to the thread. Held notifications are delivered once in the 09:00 UTC digest.',
    sections: [code('Ambient.Engine', `Agent.Schedule ("ci:main", "check ci:main again", Minutes => 10);
Agent.Advance (11); -- Agent clock, without waiting eleven minutes.
-- Tick marks due wakeups fired before dispatching them.`)],
    points: ['Wakeups survive a process restart.', 'Digest delivery marks held items delivered.', 'Step 7: 6/6.'],
    actions: [load(7), trigger('CI fails', 'ci-failed'), ['clock', '+10 min', 10], storm],
    say: ['Trigger a failure, inspect wakeups, then advance ten minutes.', 'Personal reminders use the same durable schedule.'],
  },
  {
    id: 'memory', part: 'Improve', nav: 'Step 8 · remember', step: 8,
    title: 'Short conversation, readable memory',
    lede: 'Results enter a daily journal and a per-subject Markdown file. Chat receives a small index and reads details on demand. Durable runtime state is stored separately as JSON.',
    sections: [embed('/chat?embed=1&instance=stage'), embed('/db?instance=stage&embed=1', 'State and memory'),
      cards(['Person-readable', 'preferences.md, watches.md, journal/, subjects/.'], ['Code-readable', 'Atomic JSON state stores sessions, approvals, seen IDs, pings and wakeups.'], ['Boundaries', 'Paths are confined to their root, including symlink resolution. This port uses local memory.'])],
    points: ['Reset forgets activity while preserving watches and preferences.', 'One state file belongs to one running process.', 'Step 8: 6/6.'],
    actions: [load(8), storm, ['link', 'Inspect state', '/db?instance=stage']],
    say: ['Inspect the journal after a storm.', 'Ask what happened and observe memory_read rather than a full history dump.'],
  },
  {
    id: 'protocols', part: 'Protocols', nav: 'MCP and ACP', step: 8,
    title: 'Two protocols, two jobs',
    lede: 'MCP shares the chat tool catalog with other clients. ACP connects an external worker agent, with persistent sessions, streamed updates and explicit permission handling.',
    sections: [code('MCP · the draft pinned by the local library', './ada/run.sh --mcp\n# server/discover, tools/list, tools/call\n# _meta carries protocolVersion 2026-07-28 and clientCapabilities'),
      code('ACP v2 · Ambient.ACP_Client', `Response := Adapter.Prompt
  (Session_Key => "ci", Text => Prompt, Resume_Id => Saved_Session);
-- Prompt acceptance is followed by message and state updates.
-- Wait for idle, preserve omitted fields, replace explicit content.`)],
    points: ['ACP_AGENT is an executable; use a wrapper for arguments.', 'The client declines permission requests.', 'Offline fixtures test both protocols and the Chat Completions loop.'],
    actions: [['link', 'Decision playground', '/decisions']],
    say: ['MCP exposes tools; ACP delegates a worker turn.', 'The library schemas pin the protocol revisions this program speaks.'],
  },
  {
    id: 'checks', part: 'Finish', nav: 'Verify it', step: 8,
    title: 'The same six cases, now in Ada',
    lede: 'The port keeps the original storm and evaluation contract. Integration checks use local adapters and HTTP fixtures, with no model credentials or live GitHub writes.',
    sections: [code('Terminal', 'make format\nmake build\nmake test\nmake stop'),
      cards(['Behavior', 'All nine step scores progress from 0/6 to 6/6.'], ['Protocols', 'MCP dispatch, ACP streaming and resume, Chat Completions tool calling.'], ['Operations', 'Signed webhooks, polling baseline, restart persistence, approvals, SSE and stage controls.'])],
    points: ['The original TypeScript sources remain a reference.', 'README.md documents the Ada implementation and its differences.', 'Build the smallest event loop that earns your trust.'],
    actions: [['link', 'Compare agents', '/dashboard']], say: ['Leave the dashboard open for questions.'],
  },
];
window.STAGE_CHAPTERS = chapters.map((chapter, index) => ({
  eyebrow: `Ada 2022 · ${chapter.step === null ? 'Introduction' : `step ${chapter.step}`}`,
  caption: '', ...chapter,
}));
window.STAGE_PRESENTER = Object.fromEntries(chapters.map((chapter, index) => [chapter.id, {
  min: Math.floor(index * 55 / chapters.length),
  do: chapter.say,
  cmd: chapter.step === null ? [['Terminal', 'make start']] : [['Terminal', `ada/bin/ambient_evals --step ${chapter.step}`]],
}]));
window.STAGE_FACTS = {};
window.STAGE_PROMPT_CHECKS = {};

})();
