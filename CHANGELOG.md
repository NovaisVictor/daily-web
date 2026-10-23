# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Only `main` is maintained; there are no release branches.

## [Unreleased]

### Changed
- The board is now the default view of the tasks panel. Anyone who already
  chose "Lista" keeps it; only people who never picked see the board.
- Moving a note with its buttons or the menu keeps the focus on the note, in
  its new column; it used to fall to the page.
- On a narrow panel the board shows one column at a time behind tabs, "A
  fazer n | Fazendo n | Feito n", instead of stacking the three columns.
- "Feito" shows its first 10 notes, with "Mostrar todas (n)" for the rest.
- In the list, the always-visible red "Apagar" and the small "+" for subtasks
  moved into the row's "⋯" menu, and the subtask arrow grew to 24px.

### Added
- Each task's note on the board can have its own paper and pin colour. The
  "⋯" menu of a note and of a list row has "Cor da nota…", which opens two
  choices, "Papel" (yellow, pink, blue, green, white, grey) and "Alfinete"
  (red, blue, yellow, green), each starting with "Automático". The task form
  offers the same choices when creating and editing. A chosen paper wins over
  the priority colour and over the green of a finished note; the automatic
  pin avoids the colour the chosen paper would hide, and a chosen pin that
  clashes is kept, with a "pode sumir neste papel" warning. The list shows a
  chosen paper as a small dot beside the title. Colours live in a new local
  table, `task_board_style` (migration 15), keyed by user and task id like
  "Fazendo", so they work for local and Microsoft To Do tasks; they survive
  completing and moving the task, and go away when it is deleted or its user
  is removed.
- `PATCH /api/tasks/[id]/board` accepts `paper` and `pin` (a palette colour,
  or `null` for automatic) alone or with `status`, and answers with the saved
  `{ paper, pin }`. A colour-only change corrects the cached state in place
  instead of reloading the tasks, so it never runs the Microsoft To Do CLI.
- White and grey paper tokens (`--postit-white`, `--postit-grey`) in the
  light, dark and Catppuccin themes, and a test that reads `globals.css` and
  requires at least 4.5:1 between the note's ink and every paper in every
  theme, down to the darker bottom of the note.
- The tasks board does everything the list does. Each note and each list row
  has the same "⋯" menu: Editar, Adicionar subtarefa, Agendar foco (when a
  Google calendar is connected), "Mover para" A fazer / Fazendo / Feito, and
  Apagar, which always asks first. A note's "n/m" subtask progress opens the
  checklist inside the note, where subtasks are ticked, added and deleted.
  "A fazer" and "Fazendo" have a "+ Adicionar" field at the bottom: Enter
  creates the note in that column and keeps the field open for the next one,
  Esc cancels. The columns show even with no tasks at all.
- `POST /api/tasks` accepts an optional `status` of `"todo"` or `"doing"`, so
  a task created from "Fazendo" lands there in one request. `"done"` is
  refused: completing still goes through `PATCH /api/tasks/[id]`.
- The list shows a "Fazendo" tag on tasks in progress, and both views mark an
  overdue date with the warning tone, a ▲ glyph and the words "atrasada" for
  screen readers, not with colour alone.
- The list's empty state has a "Nova tarefa" button.
- An optional board view for the tasks panel. A "Lista / Quadro" toggle in the
  panel header switches between the grouped list and
  three columns, "A fazer", "Fazendo" and "Feito", with each task drawn as a
  pinned sticky note coloured by priority. The choice is saved per user.
  "Fazendo" is kept in a new local table (migration 14) keyed by user and task
  id, so it works for local tasks and Microsoft To Do alike; "Feito" is the
  task's own completion, so moving a note there completes it through the
  existing path and moving it out reopens it. Notes move by drag and drop or
  with per-note buttons that work from the keyboard and announce the result.
- The "Resumo para a daily" dialog has a "Semanal" view next to "Diário":
  what you delivered or approved since Monday, the pull requests you opened
  since Monday and are still open, and what blocks you now. Like the daily
  one it comes from what the dashboard already loaded, and "Copiar" copies
  whichever view is on screen. It reopens on "Diário".
- A Dracula choice under "Fundo" in the account menu, next to Gradiente and
  Catppuccin. In the dark theme it applies the full Dracula palette:
  background and sidebar, raised surfaces, text, borders, the accent (Purple)
  and the status colors (Green, Orange for warnings, Red, Cyan). Like the
  others it is stored in the `backdrop` cookie and stamped on `<html>` by the
  server, so it paints on first load without a flash. Dracula is a dark
  palette, so the light theme keeps the gradient.
- A "Resumo para a daily" button in the Jira panel header opens a plain-text
  standup summary in three sections: Ontem (issues delivered or approved and
  PRs opened since the previous working day, Friday on a Monday), Hoje
  (assigned issues in progress) and Bloqueios (impeded issues and your PRs
  blocked by failing CI, requested changes or a conflict). It is built from
  the data the dashboard already loaded, with no extra request and no AI, and
  "Copiar" puts it on the clipboard. Shown only on your own view, not on a
  followed person's.
- The GitHub panel says why each pull request is stuck: CI, review and
  conflict badges, age and staleness, a "Meus PRs" tab grouped by what blocks
  each PR, and a warning when a tracked repository's default branch is red.
  It now reads everything in one GraphQL query per refresh instead of one REST
  call per repository. Row actions approve or request changes, comment,
  re-request review, merge (only when the head has not moved since it was
  shown) and re-run failed CI, each after confirmation. A linked Jira card that
  lags behind its PR can be moved to review or in progress from the row.
  Repository, author, state and search filters live in the URL, and review
  requests waiting for more than a day reach the bell.
- Jira actions straight from the panel, every one following the same contract:
  show what will change, write only on confirmation, and show Jira's own
  message when it refuses. The status on a row opens the transitions the
  workflow allows (a transition that needs fields opens Jira instead); the
  APROV badge approves or declines your own pending approval; the "⋯" menu
  marks an issue as impeded with a reason that becomes a comment, and clicking
  the row's red impediment flag clears it; "Preencher início em todas" on the
  Problems tab suggests every story's start date with the same rule as the
  per-row "Preencher início", for review before writing them all in batches of
  up to 50, with each story's outcome shown; the row's "⋯" menu comments,
  changes the due date or priority, assigns the issue to you, and creates a
  story inside an epic; and Jira mentions in the bell can be answered in
  place.
- A "Novidades" dialog shows the release notes once per browser, remembered in
  `localStorage`, and can be reopened from the account menu.
- Jira filters shared by every tab: status, type (initiatives, epics or
  stories, read from the issue type's hierarchy level rather than its name),
  and a specific initiative, epic or story, cascading so each picker only
  offers what sits under the one above. The search now also matches the key
  and title of any ancestor, so searching an initiative's name brings its
  stories. Every filter, plus the role filter, lives in the URL; switching
  person clears them, and with a filter on the tree opens fully so matches are
  not hidden in a collapsed branch.
- Each e-mail group header has a checkbox that selects or clears the whole
  group, and shows a partial state when only some of it is selected.
- Right-clicking a conversation row opens a context menu with the batch
  actions (mark read or unread, move to a folder, delete, select the row's
  group, clear selection), applied to every selected conversation. A row
  outside the selection becomes the selection first, as in a file manager.
  The menu is bound to the row only, so the opened message body keeps the
  browser's own menu for copying text.
- E-mail conversations can be grouped by account, by sender or by date
  (today, yesterday, last 7 days, last 30 days, older). The choice sits next
  to the sort control, and in the "⋯" menu on narrow screens, and lives in the
  URL as `mail_group`. Groups follow the chosen sort, a conversation belongs to
  whoever wrote to you last, and shift-click ranges follow the grouped order.
- The Jira tree now starts at the top of the hierarchy. The panel climbs from
  each issue to its objective, fetching the parents the user's queries never
  return, and nests objective, initiative, epic and story in one tree. Those
  context rows are dimmed, open by default, and left out of the project count.
- An optional Slack module using per-user OAuth: recent mentions and unread
  direct messages appear in their own panel and feed the notification bell
  and desktop alerts. The host configures one Slack app for the instance.
- Focus blocks turn tasks, Jira issues and pull requests into events in the
  person's own Google Calendar, by dragging or via the "Agendar foco" button,
  always after confirmation. The connection uses the `calendar.events` scope
  (already connected accounts must reconnect once), excludes iCal calendars and
  now stores the scopes granted by Google.
- A "Fundo" choice in the account menu, next to theme and density: the
  original iridescent gradient (the default) or the flat Catppuccin base —
  Latte in the light theme, Macchiato in the dark one. It is stored in a
  `backdrop` cookie and stamped on `<html>` by the server, so the chosen
  background paints on first load without a flash, like the other two.

### Security
- Next.js moved to 16.3.8, which closes the remote code execution in
  `next/og`'s `ImageResponse` (GHSA-vcvr-r3jv-pc5j). This app never imported
  `next/og`, so the path was not reachable here, but the package shipped with
  it. The dependency floor was raised so an install cannot fall back below the
  fix.

### Changed
- The task create/edit form shows every field explicitly. Priority and
  recurrence are native selects ("Prioridade": Alta, Normal, Baixa;
  "Repetição": Não repete, Diária, Semanal, Mensal) instead of buttons that
  cycled through hidden values. The date is a date input plus a time input,
  with "Hoje", "Amanhã", "Próx. semana" and "Sem data" shortcuts; the free-text
  date ("amanhã 14:30", "+3d") is still there under "Digitar data", with a
  live preview and an inline error that gives examples. Recurrence is
  disabled until there is a date, because a recurring task without one is
  completed for good instead of coming back. Enter saves, an empty title is
  reported on the field instead of a disabled "Salvar", and editing a task
  offers "Apagar" with a confirmation.
- The board's notes hang from a side-view plastic pushpin, in red, blue,
  yellow or green, instead of a flat dot. A pin never takes the colour its
  paper would hide, and about one note in three has its bottom corner peeling
  off. The pin rises with its note on hover.
- Choosing whose Jira is on screen moved into the panel title: "Jira · Eu"
  opens a menu with you, the people you follow, "Acompanhar pessoa" and, on a
  followed person, "Parar de acompanhar". The row of person tabs above the
  lists is gone, so the panel shows one more line of issues, and a few more
  when you follow several people.
- In the dark theme, the Catppuccin choice is now the full Mocha palette
  instead of only a Macchiato page base: background and sidebar (Base,
  Mantle), raised surfaces (Surface 0–2), text (Text, Subtext 1/0), borders,
  the accent (Mauve, with Crust text on it) and the status colors (Green,
  Yellow, Red, Blue). The light theme keeps the flat Latte base.
- The gradient is the default page background again. The Catppuccin base is
  no longer applied to everyone; it is opt-in through the new choice.

### Removed
- UI primitives that nothing imported: `components/ui/card`, `select`,
  `separator`, `sheet`, `table` and `tabs`, plus `components/data/Metric`.
  Panels keep rendering tabs through `ui/legacy-tabs`. Nothing changes on
  screen.
- The `components/ui/EmptyState` shim. Every caller already imports
  `components/data/EmptyState`.

### Fixed
- Menus and dialogs no longer let the content behind them show through in
  the dark themes. They used a 5% glass, so a post-it's colour and text sat
  under the menu items; they now use the theme's popover surface at 94%.
- Editing a local monthly task no longer wipes its recurrence. The form only
  recognised Microsoft To Do's `absoluteMonthly`, so a task stored as
  `monthly` opened as "Não repete" and saving sent `recur: 'none'`.
- The task form opens as a real dialog over the whole page instead of inside
  the tasks panel. On a 390px screen "Salvar" was below the bottom navigation
  and out of reach; now focus stays inside the dialog, Escape closes it,
  focus returns to the button that opened it, and clicking outside with
  unsaved changes asks before discarding them.
- Answering a confirmation ("Apagar a nota?" and the like) puts focus back
  where it was instead of on the page body. Inside another dialog, focus used
  to land outside it, so Tab no longer reached the form.
- Deleting a task from the list asks for confirmation first, as notes and
  e-mail already do. With Microsoft To Do behind the panel there is no trash
  to restore from.
- A repeating task now needs a date. Without one, completing it finished it
  for good while the panel announced it would come back with its next date;
  the API refuses the combination and the announcement only promises a next
  date when there is one.
- A completed note is struck through because it is completed, not because it
  is green.
- A local task with a date but no time no longer shows "none" after the date
  ("24/10 none"), and clearing a task's date no longer files it under
  "Depois". The local store kept the word 'none', which callers use to mean
  "clear this field", for the date and time; only recurrence was translated.
  Tasks saved that way before this fix read correctly too.
- Creating a focus block now shows the "Bloco de foco criado" confirmation.
  The provider called `toast()` but no Toaster was ever mounted, so the
  message was queued and never rendered. The shell now mounts one for every
  authenticated screen.
- An AI-drafted e-mail reply no longer speaks as the project's author. The
  prompt named one person, so every other user got drafts written, and
  sometimes signed, in his name. The draft is now written on behalf of the
  mailbox the reply goes out from, and leaves the signature to the sender.
- A delivered or approved story whose epic is still one of your open issues
  now shows under that epic. The server never re-fetches as an ancestor what
  is already in a list, so the tree of each tab now takes its path from every
  issue the panel knows, not only from the fetched ancestors.
- Deleting or moving an older e-mail no longer comes back as "o servidor ainda
  não refletiu esta ação". The flag re-check only covered the last 200 UIDs,
  and Gmail numbers the inbox sparsely, so a message stored below that window
  was never re-checked: the delete worked on the server, the stored copy
  stayed, and every confirmation disagreed until the action gave up. The
  re-check now reaches down to the oldest stored message, and a delete or move
  that had given up is cleared once its message is gone.
- On narrow screens each e-mail row keeps only the checkbox and the subject on
  its first line; sender, message count, time, mailbox and the "⋮" menu move to
  a second line aligned with the subject. The row no longer squeezes the
  subject into a sliver. Desktop keeps the single-line row. The sender is
  rendered twice (one copy per layout) and the narrow copy is `aria-hidden`, so
  a screen reader still reads it once.
- On narrow screens the e-mail panel moves bulk actions, filters, sort order,
  full screen and each conversation's label/delete actions into "⋯" menus;
  desktop controls and behaviour are unchanged.
- The Catppuccin page background actually shows. `<body>` carried the
  `bg-background` utility, which beats the base-layer rule that paints
  `--mesh-base`, so the page colour was always `--surface-0`: the Catppuccin
  change only removed the gradient blobs and left the dark theme near-black.
  The utility is gone from `<body>`; `--background` itself is unchanged.

### Changed
- The page background is now a flat Catppuccin base — Latte (`#eff1f5`) in the
  light theme, Macchiato (`#24273a`) in the dark one — instead of the tinted
  mesh. The five gradient blobs are transparent, so the gradient stack itself
  is untouched, and no other token moved: panels, cards, text and accent are
  exactly as they were.

### Added
- Narrow screens now have a bottom tab bar with one icon per enabled module,
  showing one module at a time and keeping the active module in `?modulo=`.
- Opt-in desktop notifications while daily-web is open in a browser tab or as
  a PWA, covering new e-mails, assigned or problematic Jira issues, pull
  requests in watched repositories, review requests, and agenda events, plus
  reminders 10 minutes before timed events. The bell contains the toggle;
  existing items are baselined on first load, and bursts over five items are
  collapsed into one summary.
- The Jira panel can follow a person — search by name, the person becomes a tab
  next to "Eu", and with it selected every list (Em aberto, Entregues, Aprovados,
  Problemas) is scoped to that person; the tab is kept in the URL (`jiraPessoa`);
  the person's lists are fetched on demand when the tab is open, not in the
  background cycle; you only see what your own Jira token can see; up to 10 people.
- Keyboard shortcuts for the two destructive batch actions on the e-mail
  list: with at least one conversation checked, `E` opens the same delete
  confirmation the row-level trash icon already used, and `M` opens a new
  confirmation that lets you change the destination folder before moving.
  Both dialogs confirm with Enter and cancel with Escape, like every other
  confirmation in the app. The toolbar's own "Excluir" button now goes
  through the same confirmation as `E` instead of deleting immediately;
  the toolbar's "Mover" button is unchanged, since it already commits to
  the folder shown in its own dropdown.
- Every confirmation dialog now prints its keyboard shortcut on the button
  itself ("Cancelar Esc", "Excluir Enter"), and the e-mail list's batch
  toolbar shows the `E`/`M` shortcuts next to the selection count. A
  shortcut nobody can see is a shortcut nobody finds.

### Fixed
- The notifications popover now fits narrow screens instead of overflowing
  the left edge.
- The notification bell no longer disappears when Jira is off but e-mail or
  pull requests are on.
- The Jira person tabs wrap onto new lines, next to their buttons, instead of scrolling sideways. With
  several people followed and one selected, the strip plus its buttons was
  wider than the panel and pushed it into scrolling both ways.
- The Jira "Problemas" list no longer flags archived issues (status
  "Arquivado"/"Archived"). They are filtered after the search rather than in
  the JQL, because Jira rejects a status name that does not exist in the
  instance.
- An opened e-mail's body can be selected and copied again, and its links are
  clickable. Both were broken by the same conversation row: it carried
  `draggable` (for dragging a thread into a folder) on the `<li>` that also
  contains the opened message, and browsers block native text selection
  inside a draggable ancestor. `draggable` now lives on the row header only,
  which is also the only part that should start a drag.
- A link inside an e-mail survives being flattened to plain text. The reader
  shows a `text/plain`-style view built by stripping every HTML tag, which
  used to erase a link's `href` along with the tag, leaving unclickable
  visible text and no address at all when the link had none (an image
  button, say). The address is now kept next to the text — or shown on its
  own when there was no text — and any URL in the resulting body, including
  ones the sender wrote as plain text, is rendered as a real, clickable link.

### Changed
- Dependencies brought up to date: the `@anthropic-ai/sdk`, `lucide-react`,
  `mailparser`, Next.js, React and React DOM, and `tailwind-merge` production
  group; the `@types/react`, `@types/react-dom`, `@vitejs/plugin-react`,
  `@types/node`, and `@types/nodemailer` development group; Vitest 5;
  nodemailer 10; and imapflow 2. imapflow's 2.0 release migrated to
  TypeScript and narrowed `envelope.date` from `Date` to `Date | string`,
  which broke the type check in `lib/integrations/imap.ts`; the envelope
  date is now normalized through `new Date(...)` before formatting.

### Added
- A "Revisões" tab in the GitHub panel lists the pull requests waiting for the
  user's review, from any repository the token can see — the tracked-repo list
  has nothing to do with it. It is one search call per cycle
  (`is:open is:pr review-requested:@me`), never one call per repository. The
  tab shows only what is still awaiting his review: GitHub drops the review
  request once the review is in, so what he has already reviewed leaves the
  list on its own. Each row carries the repository (with a link to it), the
  number, the title, the author and how long the request has been waiting.
  The tab lives in the URL as `?pulls=revisoes`; the default tab stays out of
  it and an unknown value falls back to the default.
- An empty list now says which kind of empty it is. A classic token without
  the `repo` scope, or a fine-grained token, cannot see review requests in
  repositories it was not granted — the tab says so and what to do about it,
  instead of showing a silent empty list. A refused token (401) and a missing
  permission (403) surface as errors, and a 403 for rate limit now reports how
  much is left and when the quota comes back. One page of results is the cap;
  when the search has more, the tab says how many it is showing of the total.

### Fixed
- The GitHub panel scrolls inside its card like the other panels do. It was
  entering the grid frame inside a `div` with no height, which broke the
  chain of heights down to its body: the list grew past the card instead of
  scrolling in it, taking the tabs and the tracked-repos drawer out of reach.
  The body now has a real height, only the list scrolls, and the scrollbar has
  a gutter of its own so it does not land on top of the rows — the same
  treatment the notes panel already got. On a narrow screen the panel keeps
  the stacked, page-scrolling behaviour every panel has there. This panel has
  no maximized view.

### Added
- A note and a folder can be created from inside the maximized notes view.
  The tree in the dialog now has a header with the same two actions the card
  has, and a line saying where the new thing will land — "Criar em: Trabalho /
  Clientes" — because the card's header is behind the dialog and the creation
  would otherwise be blind. The note is created in the selected folder, or
  with no folder when the context is "Todas as notas" or "Sem pasta"; it
  becomes the active note with the cursor already in the text, and the dialog
  stays open. The folder is created under the selected one, or at the root,
  and opens for its name right away, with the same limits and the same errors
  as the card — which are now also shown inside the dialog. Whatever was being
  typed is saved before the new note takes over. While the dialog is open the
  card hands its own two buttons over, so there is one of each on screen.

### Fixed
- A note created outside the notes panel — from an e-mail, today — now shows
  up in the panel without reloading the page. The panel reads `/api/notes`
  once when it mounts, so it had no way of hearing about a note created by
  another part of the same page; it now also listens for the
  `daily-web:notes-changed` window event and reads the list again. There is no
  timer and no polling behind it: the event fires once, when whoever created
  the note says so.

### Added
- `lib/notesBus.ts` is the contract for that event. `notesChanged()` tells the
  panel to read its list again, and `notesChanged({ activate: noteId })` also
  leaves that note open — selected, with its folder expanded and any search
  cleared — which is what an "Abrir" button next to a created-from-e-mail
  confirmation needs. The active note used to be internal state with no way in
  from outside. An unknown id just refreshes the list. Reading the list again
  never overwrites what is being typed: only the note that is being opened
  puts text in the editor, and a pending save is flushed before that happens.

### Added
- An e-mail can become a note or a task, from an actions menu on its row — in
  the dashboard card and in the full-screen panel alike. The menu is the design
  system's, so it opens and is walked with the keyboard.
  The note takes the subject as its title and the message as its text,
  converted from the mail's HTML to Markdown: paragraphs, headings, lists,
  quotes, code, bold, italic, links and images survive, and no markup does —
  the body of a stranger's e-mail is never injected as HTML into a note that is
  later rendered, and an address that is not http, https or mailto keeps its
  text and loses its link. The destination folder is chosen in the menu and
  defaults to "Sem pasta".
  The task takes the subject and the sender's name, falling back to the address
  when the sender sent no name, and nothing of the body.
  Creating confirms on screen and offers to go to the panel where the note or
  the task now is. A repeated click cannot create two: the menu is locked while
  the request is in flight, and the server answers a second request for the same
  message with the first creation for a minute afterwards.
- Several e-mails can be selected in the dashboard card and dragged onto one
  of three targets — mark as read, mark as unread, delete — which appear when
  the drag starts, carry the count of what is being dragged, and say what they
  will do while the cursor is over them. The action runs only on a drop over a
  target, so letting go anywhere else is how you change your mind, and the
  same three actions stay available as buttons for anyone not dragging.
  Deleting moves to the provider's trash, and the list and counters are re-read
  afterwards.
- When part of a batch is not processed, the panel now names the messages that
  were left out and why, and offers to retry only those instead of the whole
  batch.
- The folder sidebar is grouped by account. Each account carries its own
  folders, counters and state, collapses on its own, and two folders with the
  same name are told apart by the account they belong to. An account whose
  sync fails shows its error and a retry beside its own heading, and the other
  accounts keep working.
- The folder list of each account is served from the database, so the panel
  opens with what it already knows instead of waiting for one round trip per
  folder. A background sync runs on open, announces itself with a discreet
  spinner in the account's heading, and replaces the tree in place — a created,
  renamed or deleted folder appears with no reload, no closing and no
  interruption, keeping the selected folder, the collapsed accounts and the
  scroll where they were. Two opens at once share one sync per account.

### Fixed
- Dragging an e-mail works again — onto the action targets in the dashboard
  card and onto a folder in the modal. Our own dragstart handler was marking
  the row and applying the bundle's gather transform while the browser was
  still deciding whether to open a drag session; repainting the drag source
  there makes Chromium abandon the drag without an error. Every state change
  now waits for the frame after dragstart. The component tests had passed
  throughout because a dispatched DragEvent never asks for a drag session, so
  it could not notice one was being refused.
- A drop onto a folder of another account is refused with a message instead of
  moving the message inside its own account. IMAP moves within an account;
  copying and deleting across two is a different operation. The check reads the
  account of the messages being dragged: it used to read the account of the
  open folder and, in the unified inbox where no folder is open, fell back to
  the first account configured — so every drop of a message from any other
  account was refused even when it landed on that account's own folder. A
  selection spanning two accounts is refused too, since one move cannot serve
  both.
- A note created from an e-mail now shows up in the notes panel straight away,
  and the confirmation's button opens that note, using the panel's documented
  change event.

### Fixed
- Selecting another folder now changes the listed messages. The listing is
  keyed by the (account, folder) pair — the path alone is not an identity,
  since two accounts each have their own INBOX — a folder already read is shown
  from cache while it refreshes behind, and a late answer for the folder you
  just left can no longer replace the one you are looking at. Changing folder
  clears the message selection and the list fades in without holding anything
  back. An empty folder, a folder that fails to open and a folder still loading
  now each say so.
- The "mark folder as read" button no longer sits on top of the unread count.
  Name, counter and action each have their own column, at any width, and the
  button explains in a tooltip that it marks that folder in that account —
  including what was never loaded here — which is not the same as marking the
  selected conversations.
- Notes live in folders and subfolders. The panel shows a tree with "Todas as
  notas" and "Sem pasta" above the hierarchy, folders expand and collapse, and
  a note moves between them by the row menu or by being dragged onto a folder;
  a folder moves the same way. Notes that already existed start with no folder.
  Deleting a folder says beforehand how many subfolders and notes it holds and
  never deletes a note: everything inside goes to "Sem pasta" while the
  subfolders go with it. The tree is bounded — at most 100 folders per person
  and five levels deep, and a move that would put a folder inside itself or
  push the branch past that depth is refused.
- The folder tree is mirrored in the Google Drive copy: inside the app's
  folder, each note folder is a Drive folder tagged with its `folderId`, and
  each note's `.md` file sits in the mirror of its own folder — a note with no
  folder stays at the root. Renaming or moving a folder renames or moves the
  mirror instead of creating a second one, and deleting one sends the mirror to
  the Drive trash after its notes have moved out. What ties the two sides is
  the id, not the name or the path, so renaming a folder inside Drive breaks
  nothing. The sync stays one-way — what comes back from Drive is still only
  the restore, and it now rebuilds the tree along with the notes.
- Searching notes: one field that matches the title or the body, ignoring case
  and accents, debounced while typing. Each result shows the title, a snippet
  around the match and the folder path, and opening one opens the note. The
  search is global by default and can be restricted to the selected folder and
  its subfolders; clearing it brings back the tree exactly as it was.
- The maximized note keeps the same tree on the left and the note on the right.
  The active note is highlighted, switching notes never closes the dialog, and
  the selection and the expanded folders survive maximizing and restoring.
  Switching notes flushes the pending save first, so nothing typed is lost. On
  a narrow screen the list collapses to give the editor the whole width.

### Fixed
- A long note no longer pushes the formatting toolbar out of the card. The
  editor now has a definite height inside the panel, so the text scrolls in its
  own area and the toolbar, the preview toggle and the maximize button stay put
  — in the dashboard card, in the maximized view and at narrow widths.

### Changed
- The inner cards on the settings screen — each saved connection and the form
  that edits it — are translucent surfaces over the gradient instead of the
  near-black `surface-1`, with a discreet border and hover and focus states.
  All modules render through the same markup, so E-mail, Agenda, Jira and the
  rest are identical to each other.

### Added
- A whole folder can be marked as read from the folder tree, including the
  messages too old to have been synced here — one intent recorded for the
  folder, one search and one flag command on the server, never one per
  message. A tentative touches at most a capped number of messages and what
  is left over goes to the next one, and a folder with many unread asks for
  confirmation first.
- Messages are moved between folders by dragging them onto the folder tree.
  The move is a real IMAP move, it goes through the same durable log as every
  other action — the message leaves the source folder as soon as the intent is
  recorded, and a move that runs out of attempts brings it back with the error
  on its row. A move onto the folder the message is already in is refused, and
  so is one onto a folder the server never announced.
- The message list selects like a file manager: a click replaces the
  selection, ctrl/cmd+click adds or removes one, shift+click takes the range
  from the anchor, and the checkbox always toggles. The list takes focus, so
  the arrows walk it, shift extends, space toggles, ctrl/cmd+A takes
  everything visible and Esc clears — without closing the full screen behind
  it. The row under the keyboard carries a ring so the arrows are not blind.
- Dragging one row of a selection drags the whole selection, and dropping it
  moves the batch in a single operation. The selected rows gather into a stack
  while the drag is on and the cursor carries a bundle with a count, so it is
  visible that the operation is a batch. None of that happens for a reader who
  asked for less motion.

### Added
- Mailboxes other than the inbox can now be read. `GET /api/email/mailboxes`
  returns the account's folder tree with the total and unread count of each
  folder, and `GET /api/email/messages` lists one folder at a time under an
  explicit cap. The tree is stored and reused for ten minutes, because
  counting a folder costs one round trip to the server per folder, and a
  server that fails to answer leaves the stored tree standing rather than
  emptying the panel.
- Mailbox actions carry the folder they act on. A message is identified by the
  folder it lives in and the numbering that folder announced, so an action
  recorded before the server reindexed a folder now fails in the open instead
  of landing on whichever message inherited the uid.
- The e-mail panel opens full screen, with the account's folder tree beside
  the list: a folder is picked from the tree and its messages are listed in
  place, the same reading and acting the inbox already had.
- What the panel is showing now lives in the URL — folder, search, unread
  filter, account, ordering, the open message and full screen. Reloading, the
  back button and sending yourself the link all land in the same place.
  Changing folder or opening full screen is navigation and the back button
  undoes it; touching a filter is not, so typing in the search box does not
  fill the history. A default is never written to the URL, and a value that
  makes no sense falls back to the default instead of becoming state.

### Fixed
- A deleted e-mail no longer comes back, and neither does one that was marked
  as read before being deleted. Every mailbox action is now written to a
  durable log before it reaches the server, and each snapshot the server
  returns is reconciled against that log instead of overwriting it: the
  message stays out of the list until the server agrees, survives a restart of
  the service, and is retried with bounded attempts and exponential backoff
  when the write fails. An action that runs out of attempts brings the message
  back with the error on its row, because it really is still in the mailbox.
- Every IMAP operation for one account now waits its turn in that account's
  queue. Listing holds a connection for seconds, and an action fired meanwhile
  opened a second login that the provider refused — which is how a delete
  failed and the message returned to the screen.

### Changed
- The background cycle runs every five minutes instead of every minute. One
  minute was more often than a mailbox changes, and it kept a login open on
  every account twelve times an hour for nothing. Manual refresh is unchanged,
  and the countdown in the header still comes from the server, so it needs no
  edit to follow the new cadence.
- Applying a label is now its own action, separate from moving. Both used to
  travel as "move" while only ever copying, which is what a Gmail label is;
  moving a message out of a folder had no way to be asked for.
- The e-mail panel no longer renders its list twice while full screen. The
  copy behind the dialog duplicated every row in the accessibility tree and
  made both copies fetch the same folder.
- The inbox and the sent folder are fetched over one connection again. The
  login is the expensive part of a round trip to Gmail, and opening a second
  one per account each cycle cost more than the whole fetch saved.
- The refresh cycle no longer re-reads a whole mailbox to find out that
  nothing changed. Messages already read from the server are kept, and each
  cycle asks for two things over one connection: what arrived after the last
  uid it knows, and the flags of a recent window of uids — which is how a
  message read, labelled or deleted in another client catches up here. Nothing
  is concluded about what lies outside that window, because nothing outside it
  was asked. A folder's stored copy is capped, and a folder the server
  reindexes is dropped and read again.
- The active note tab is the same band as the sidebar's active item — a brand
  tint fading out with a 3px bar — instead of a solid surface that read as a
  black block in the dark theme, with a brand bar that curved around the tab's
  rounded corner.
- The front end is rebuilt on Tailwind v4 and shadcn/ui. The hand-written
  stylesheet is gone, replaced by a token layer in `oklch()`: a six-level
  surface ramp, five elevations that each open with a large inset highlight,
  fixed signal colours independent of the accent, and an iridescent mesh the
  whole page floats on. Panels, dialogs and popovers are translucent surfaces;
  buttons, chips and status pills are round; containers follow a radius ladder.
- Type is seven roles, each carrying family, size, leading, weight and tracking
  together, so a size is never chosen alone at a call site. Every stray size
  below the 13px caption floor was routed to the role it wanted, uppercase
  micro-labels with wide tracking are gone, and numbers use the text face with
  tabular figures rather than the mono face.
- Status is never hue alone: each state carries a glyph and a label beside the
  colour, so the reading survives a grayscale print. No status follows the
  accent, since a status that did would change colour when the accent changed
  with nothing about the status having changed.
- The screens gain an app shell: a recessed sidebar whose active item is a band
  with a 3px bar rather than a pill, a command palette on Cmd+K over routes and
  settings, and an account block. The frame is pinned to the viewport, so the
  mesh stays still while only the content column scrolls.
- The hour-driven ambient background is removed along with its module and test.
  The system paints a fixed mesh instead, on the ground that the accent stays
  the colour of action while the background is atmosphere.

### Added
- The Jira panel has a "Problemas" tab listing your stories and epics
  (assignee or reporter, open or updated in the last 30 days) with
  data-quality problems, each with every problem it has and a link to the
  issue: a story in progress without a start date, a done story without a
  start or resolution date, a story without an epic, an epic without stories,
  and an epic in progress with no story in progress. The start date is found
  by field name ("Start date" / "Data de início"); if the instance has no such
  field the tab says so instead of flagging every story. Epic children come in
  one paginated `parent in (...)` search, not one request per epic.
- The active Jira tab lives in the URL (`?jira=…`), so reloading, going back
  and sharing the link land on the same tab.
- A note can be renamed from a pencil beside its tab, not only by
  double-clicking it. Enter saves, Escape cancels, and an empty title keeps the
  old name. The Drive copy follows: the next sync renames the same file rather
  than creating a new one.
- A note opens full screen from a maximize button at the top right of the
  editor, in the app dialog, with the toolbar, the preview and the save status.
  Focus lands in the text; Escape or the restore button brings it back to the
  panel with focus in the panel's text, and whatever was typed is saved before
  the switch.
- Quick notes can keep a durable copy in the user's own Google Drive, so they
  no longer depend on the machine that serves the app. **Guardar no Google
  Drive** in the settings screen connects one Google account per user with the
  `drive.file` scope, which only reaches files the app created. Each note is a
  `.md` file in a *daily-web — notas* folder, uploaded a few seconds after each
  change; failures leave the note pending and it is retried on the next change
  or the next time the notes are opened. Deleting a note moves its file to the
  Drive trash. On a fresh install, connecting the same account restores the
  notes. The copy is one-way, and notes that existed before this change are
  not bulk-uploaded — each goes up the next time it is edited. The OAuth flow
  reuses the calendar's client and redirect URI; the signed `state` now carries
  what the authorization is for.
- Notes are Markdown. The editor gets a formatting toolbar, keyboard shortcuts
  (bold, italic, strikethrough, inline code, link) and list continuation on
  Enter for bullet, numbered and task lists; **Visualizar** renders the note
  with GitHub-flavoured Markdown — tables, task lists, fenced code with syntax
  highlighting, links opening in a new tab. Rendering is sanitized: raw HTML
  is dropped, the tree goes through GitHub's allowlist, and `javascript:`-style
  URLs are stripped. New dependencies: `react-markdown`, `remark-gfm`,
  `rehype-sanitize` and `rehype-highlight`.
- Theme is three states — system, light and dark — where system is the absence
  of both a class and a cookie. Both legs of the dark palette are written out,
  so an explicit light choice wins on a dark machine and an explicit dark choice
  wins on a light one. The choice is stamped during server render, so there is
  no wrong-theme flash on first paint.
- A display density setting beside it, comfortable or compact, changing vertical
  rhythm only: a dense screen needs more visible lines, not smaller type.
- Screens use the full width of the display. The content column was capped at
  1280px, which on a wide monitor was empty margin on both sides of a panel
  that is dense on purpose. Frame padding and vertical rhythm tighten with it.
- Controls whose glyph says it all drop their label: the bell with its count in
  a round badge, refresh as a spinner that actually spins while it works, the
  pomodoro's play and pause, a broom to reset it, the mail batch bar's mark,
  move and delete, a plus for every add (note, task, subtask, repository,
  watched issue), a pencil and a bin on a connection, a key to change a
  password, checks to mark notifications read, and the grid's arrange and
  discard. Dropping a label is a space decision and must not become a
  meaning one, so every one of them keeps its words in a tooltip and in its
  accessible name — a shared component makes that the only way to build one.
- The header counts down to the next background refresh ("próxima em 9:41"),
  so a screen that has not changed in a while reads as "waiting for the next
  cycle" rather than "stuck". The server announces the time of its next tick
  in the dashboard state; the page only ticks the local clock down.
- The sidebar collapses to a 56px icon rail on Cmd+B or from its own control,
  which gives a vertical monitor back 184px of width. The choice rides a cookie
  the server reads during render, so a collapsed rail never expands for a frame
  on reload, and each item keeps its label in a tooltip and for screen readers.

### Fixed
- The Jira "Problemas" tab no longer reports every closed story. The rule
  "concluída sem data de conclusão" flagged a done story whose `resolutiondate`
  was empty, but in this Jira instance most workflows never apply a resolution
  on the transitions that finish a card, so that field stays null on issues
  that are legitimately closed — 93 issues were reported for a field the
  operation does not feed. Taking "done" from the status category instead makes
  the rule say only "a done story is done", so it was removed along with its
  label and the `resolutiondate` fetch, which nothing else used. The other five
  rules are unchanged.
- Panels can be resized again in "Organizar" mode. The rule that stops panel
  content from catching the pointer while arranging was widened to every child
  of the grid item in the Tailwind rebuild, which also caught the resize handle
  the grid injects there: pulling the corner moved the panel instead of
  resizing it. The handle is now excluded from that rule.
- The background refresh now reaches the screen. The production build bundles
  the refresher once for the startup hook that runs the loop and again for the
  API routes, and each copy kept its own cache: the loop refreshed a cache no
  route read, so the dashboard only changed when someone clicked refresh, and
  the next-refresh countdown never appeared because the routes never saw the
  loop's schedule. The refresher's state now lives on the process, shared by
  every copy.
- The background refresh runs every ten minutes by default instead of every
  minute, and `REFRESH_SECONDS` is validated: an empty or non-numeric value
  used to reach `setInterval` as `NaN`, which fires every millisecond. Any
  invalid value now falls back to the default. A tick that arrives while the
  previous cycle is still running is still dropped, not queued.
- The pointer cursor is back on everything clickable. Tailwind v4's preflight
  leaves buttons on the arrow, unlike v3, and on a dashboard where nearly every
  control is a button that reads as "not clickable" on almost everything. It is
  set once in the base layer rather than per component, so a control added
  tomorrow cannot forget it, and a disabled control now shows `not-allowed`
  instead of giving no reason for the click that did nothing.
- Deleting anything asks in an app dialog instead of the browser's own. The
  native one cannot be styled, cannot be reached from the keyboard beyond its
  two buttons, blocks the whole tab, and on some platforms is suppressed
  outright — a destructive action that silently never asks is worse than one
  that asks badly. Escape cancels, Enter confirms, focus lands on the confirm
  button, and cancel comes first so the destructive button is never the one a
  hand lands on by habit.
- A focused control on a panel's first row no longer has its ring sliced off.
  The ring reaches 4px past its control and that row sat flush against the
  scroll container's clipping edge.
- A panel's frame no longer scrolls away with its rows. The card sat inside the
  scroll container, so scrolling a long list carried the border and the rounded
  corners off the top and the module stopped reading as a box. The card is now
  the grid item itself, pinned to the module bounds, with the header fixed and
  only the content moving under it.
- The notification menu no longer paints under the page. It was positioned
  inside `<main>`, which scrolls and sits among panels that carry a
  backdrop-filter, and a backdrop-filter creates a stacking context no z-index
  can climb out of. The panel is portalled to the body and positioned against
  the trigger.
- The Jira "Em aberto" tab stops breaking in a narrow module. Its meta line
  wrapped mid-phrase, splitting "Em andamento" across two lines and stranding
  the status glyph on its own. Each meta item is now indivisible and the row
  wraps between them.
- `.gitignore` anchors its SQLite pattern to `/data/`. Unanchored, `data/`
  matched any directory of that name at any depth, which silently kept
  `components/data/` out of both git and the CSS content scan — its utilities
  never reached the stylesheet and its files were in no commit.
- The systemd unit restarts on any exit, not only on failure. An external
  SIGTERM exits cleanly, and a clean exit is not a failure, so the service
  stayed down until somebody noticed rather than coming back on its own. A
  deliberate `systemctl stop` still stops it for good, and the
  `systemctl restart` in `deploy/publish.sh` is unaffected.

### Added
- A third tab, **Aprovados**, listing what you approved. There is no JQL
  function for it: `myApproved()` and `myDecided()` do not exist,
  `approvedBy(currentUser())` is rejected because the `approvals` field takes no
  function with an argument, and `approved()` on its own answers "approved by
  anyone" — it returns other people's decisions. What narrows it to you is the
  transition out of the approval status having been yours, the same trick
  **Entregues** already uses. Unlike every other query in the module, this one
  names a status: without `FROM "Aprovação"`, an issue approved by someone else
  joins the list the moment you touch its status, which was measured against the
  Service Desk approval API — 8 of 9 correct without it, 7 of 7 with it. The
  cost is known and deliberate: if the workflow renames that status, the tab
  goes quiet.
- **Entregues** and **Aprovados** can be read by day or by week. Both default to
  today, as before, and a **7 dias** chip widens them. Both lists arrive already
  covering the week with a mark on what falls in today, so switching the period
  is a cut over what is already in memory rather than another round trip — and
  the day boundary stays the one Jira uses (`startOfDay()`, in your profile's
  timezone), not a date computed in the browser. The period belongs to both tabs
  at once: the two lists answer the same question about two different events.
- **Em aberto** also lists what is waiting for your approval. Until now the tab
  answered "what is assigned to or reported by me", which left out the requests
  that only need a decision from you — they belong to someone else and never
  showed up. The query asks Jira for `approvals = myPending()`, the one thing
  that separates an approval waiting on *you* from an issue merely parked in a
  status called "Aprovação", which may be waiting on somebody else. An approval
  carries an `APROV` badge, joins the same hierarchy and project grouping as the
  rest, and an issue that is both yours and pending your approval stays a single
  row. Approving is not one of the roles, so these issues also survive the
  Responsável/Relator filter: narrowing by role no longer hides what is asking
  you for a decision.
- **Marcar todas como lidas**, in the notification bell. The bell holds up to
  20 items per source across three sources, so emptying it one row at a time
  cost up to 60 clicks. The button sits above the list with the unread count
  beside it, and appears only when there is something to dismiss. It sends the
  ids that were on screen when you clicked, in one request, and the badge drops
  before the server answers, as the single row already did. A malformed id
  fails the whole batch instead of writing part of it, which would leave the
  screen claiming everything was read while the rest came back on the next
  cycle. Dismissing an email notification still does not mark the email as
  read on the server.
- The Jira panel is split into two tabs. **Em aberto** holds what the panel
  always showed, the issues where you are the assignee or the reporter, and
  **Entregues** lists the ones you closed today, in the same shape: the
  hierarchy, grouped by project, so a service request in PDS does not sit
  next to a story in DAD. A delivered issue reads its status in green,
  the only situation that asks nothing more of you. The query names no
  status: it asks for issues currently in the Done category whose status you
  changed today, or that were resolved today under your name, so a workflow
  that closes in "Resolvido" and one that closes in "Done" both work.
  Something you closed and someone reopened is not delivered, and does not
  appear.
- The repository name in the pull requests panel links to the repository on
  GitHub. Pull requests and issues already linked to their own pages; the
  repository heading was the only name on the panel that was not clickable. A
  name that is not in `owner/name` form stays plain text instead of becoming a
  broken link.
- The notification bell now covers three sources instead of one. An open pull
  request and an unread email raise a notification alongside the Jira
  mentions, both derived from what the refresh already loaded — no extra call
  to GitHub or IMAP. Each source contributes at most 20 of its most recent
  items, so a full inbox cannot bury the rest. Dismissing an email
  notification does not mark the email as read on the server: they are
  separate actions.
- The dashboard arrangement is saved per screen size. **Salvar para esta tela**
  records the exact window width and height alongside the arrangement, and on
  load the closest saved size wins — so opening the DevTools or a bookmarks bar
  does not drop you back to the default, while a different monitor keeps its
  own arrangement. Up to 20 sizes per user; saving again at the same size
  replaces it.
- **Notas rápidas**, a new module: a notepad with tabs, kept on the server so
  the notes follow you between machines. Tabs run down the left side and the
  column scrolls on its own when there are many, so the panel stays inside its
  cell on the grid. Text saves itself as you stop typing, on leaving the
  field, on switching tabs, and on closing the page. Double-click a tab to
  rename it. It needs no credential, so it is on from the first login; the
  settings screen only offers the on/off switch.
- The Jira hierarchy expands and collapses, with the same disclosure arrow the
  tasks use. Branches start closed, so the panel opens on the top of each tree
  and you descend where you care; an issue with nothing under it gets a spacer
  instead of an arrow, not a control that does nothing.
- A conversation includes the messages you sent. The Sent folder is read
  alongside the inbox and merged into the thread, so a reply-to-a-reply reads
  as a dialogue instead of a monologue. Sent messages take part in
  conversations but never become inbox rows of their own, and they stay out of
  select/tag/delete: those act on the inbox, and deleting a conversation
  should not destroy your own copy of what you wrote.
- The inbox groups a conversation into one row. The subject loses its stack of
  "Re:"/"Fwd:" prefixes, the row shows who took part and how many messages
  there are, and opening it lists them in the order they happened. A
  conversation of one message opens straight into the body, as before.
  Messages are linked by their References/In-Reply-To headers, and — within a
  single account, where it cannot cross-match — by normalized subject, which
  rescues the threads whose headers a client dropped.
- The quoted history inside a message body folds behind a "···" button, so a
  reply to a reply shows what the person actually wrote. The attribution line
  is recognized in Portuguese, English, Spanish, French and German, since one
  thread commonly passes through clients in different languages.
- Jira issues you do not own can be watched by key. Add `ABC-123` under
  **Acompanhando** and it is fetched alongside your own; the `×` next to it
  stops watching. Keys are validated before reaching JQL, and the row leaves
  the list immediately rather than waiting for the next Jira fetch.
- Shift+click selects a range of messages, as in Gmail: click one, hold Shift
  and click another, and everything between them takes the state of the
  message you clicked.
- Pull requests are grouped by repository, with issues and pull requests as
  separate lists inside each. The `/repos/{repo}/issues` endpoint returns both
  in one list, so a flat list mixed them.
- Scrollbars are styled to match the app instead of falling back to the
  browser default, which the resizable grid made visible everywhere.
- The dashboard is rearrangeable: **Organizar** enters a mode where panels move
  by dragging and resize by the corner, and **Concluir** leaves it. The
  arrangement is stored per user.
- The Jira panel now shows status, staleness and due date on each row.
  Six issues turned out to be past due, which the panel had no way of
  showing before.
- Contribution infrastructure: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  `CODEOWNERS`, pull request and issue templates, Dependabot.
- CI on GitHub-hosted runners (tests, build, audit of production dependencies)
  and deployment on a self-hosted runner, triggered only by pushes to `main`.
- `LICENSE`. The README had linked to it since the first release, but the file
  did not exist, so GitHub reported the project as "Other".

### Changed
- Each refresh cycle logs one line, `refresh.cycle`, with its duration and the
  panels that came back with an error. A degrading cycle used to be visible
  only as a panel that stopped moving.
- The arrangement is saved when you ask, not while you drag. **Organizar** now
  leads to **Salvar para esta tela** and **Descartar**, and nothing reaches the
  server until you pick one — so a layout you messed up costs nothing.
- Rearranging is entered only through the **Organizar** button. Holding Ctrl
  used to enter it as well, which meant a modifier key silently changed what a
  click did anywhere on the dashboard.
- **Restaurar disposição** moved from the dashboard to the settings screen,
  where the rest of the per-user configuration lives.
- Production now runs from `/srv/daily-web` instead of the development
  checkout, so a deploy cannot overwrite uncommitted work.
- Documentation is in English. The interface stays in Portuguese.
- The Jira row no longer shows the assignee/reporter badge by default. It read
  the same on 15 of 19 issues, so it occupied the only visual slot on the line
  without carrying information; status, which has five distinct values, took
  its place. Reporter is still marked, because it is the exception.
- Outside the hierarchy view, issues group by situation rather than project.
  Grouping by project barely grouped anything when 16 of 19 belong to one.
- Dependencies brought up to date: React 19.2.8, Vitest 4, Vite 8,
  `@vitejs/plugin-react` 6, better-sqlite3 13, and the checkout and setup-node
  actions to v7.
- `vite-node` is now a direct dev dependency. It used to arrive through
  Vitest 2, which no longer ships it, and `npm run users` depends on it.
- Dependencies brought up to date again: bcryptjs 3, TypeScript 7, jsdom 30,
  and the `@types` for node and better-sqlite3. bcryptjs is the only one that
  reaches production; hashes written by version 2 still verify, which was
  checked against hashes generated before the upgrade, so stored passwords
  keep working. New hashes are written as `$2b$` instead of `$2a$`.

### Fixed
- The email panel no longer goes stale until you press refresh several times.
  Three sources of IMAP contention were making the automatic cycle fail: body
  warming opened one connection per message, so a cycle with thirty new emails
  attempted thirty logins per mailbox and the server started rejecting them
  with an authentication failure; a cycle that ran past the interval had the
  next one start on top of it; and the refresh button opened a second read
  alongside the running cycle, so clicking again made the contention worse
  instead of better. Body warming now fetches through a single connection per
  account, capped per cycle; a tick is skipped while the previous cycle is
  still running; and a refresh requested while one is in flight — from the
  button or from the loop — receives the result of the one already running.
- A mailbox whose socket dropped outside a command no longer takes the whole
  process down. The IMAP client had no `error` listener, so the failure
  surfaced as an uncaught exception, and the connection teardown could reject
  on its own and mask the real error.
- Deleting an email no longer brings it back a few seconds later. A refresh
  cycle reads the mailboxes at the start and only writes the cached dashboard
  state at the end, so an action taken in between was overwritten by a
  snapshot that predated it — the message reappeared on the panel until a
  later cycle read the mailbox again. Actions applied while a refresh is in
  flight are now replayed on top of its snapshot before it becomes the cache,
  which covers marking as read, unread and moving as well.
- Marking a notification as read works for pull requests and emails. The
  notification id was going into the URL path, and a pull request id carries
  both `/` and `#` — the `#` opened a fragment, so the browser dropped the
  `/read` and the request never reached the route. The id now travels in the
  request body, which also covers the email ids, since a Message-Id is free
  text and does not belong in a path.
- The bell is ordered by when things happened, newest first. The sources were
  concatenated one after another, so a message that had just arrived landed at
  the bottom of the list, behind pull requests from weeks earlier.
- Marking a notification as read now records the source it actually came
  from. The route had `jira_mention` hard-coded, which was invisible while
  Jira was the only source; with three, a dismissed pull request or email was
  written under the wrong key and came back on the next cycle. The bell also
  labelled every notification `JIRA` for the same reason.
- Email tags now survive a reload, and tags applied in Gmail itself show up in
  the daily. The panel only ever kept tags in component state, filled in when
  you clicked — so a refresh emptied it and a tag created anywhere else never
  arrived. The envelope now carries the labels the server reports
  (`X-GM-LABELS`), and the row reads from those; the click stays optimistic
  until the next refresh confirms it. Accounts without the Gmail extension
  report no labels and behave as before.
- Saving the layout no longer fails for a tab opened before the deploy. The
  previous client saved on every drag and sent no window size, and the new
  route rejected that with "tamanho de tela inválido" — in the middle of the
  drag. A request without a size now falls back to the single arrangement,
  which is what that client always wrote; only a size that is present and
  nonsensical is still refused.
- A module with no fields no longer offers a **Conectar** button that opens an
  empty form.
- An IMAP uid is per mailbox, so the same number means different messages in
  the inbox and in Sent. The mailbox now travels with the id through the body
  route, the body cache (whose primary key gained a `mailbox` column) and the
  state patches — without it, opening a sent message would have returned an
  unrelated inbox message's body.
- Acting on several messages at once no longer fails. Each target opened its
  own IMAP connection, so a batch of 27 deletions asked for 27 simultaneous
  connections and the server refused 24 of them with "Too many simultaneous
  connections". Targets are now grouped per account and sent as a single IMAP
  command over one connection — which is what the protocol is for, and much
  faster besides. Message ids are checked to be digits before they are joined
  into a sequence set, where `-` and `:` would otherwise form a range and
  reach messages nobody selected.
- A second Google calendar can now be connected. The connection is identified
  by the account that authorized it, so reconnecting the same one renews its
  access while authorizing another adds a calendar. Previously any Google
  connection was overwritten, so the second account erased the first.
- Shift+click selected only the message clicked. The anchor was read inside
  the state updater, which React runs after the anchor has already moved to
  the item just clicked — making every range one item long.

## [0.2.0] - 2026-08-26

### Added
- Per-user integrations. Each person registers their own credentials from the
  settings screen; nothing is shared between users.
- Google Calendar over OAuth, as the reliable path for Google accounts.
- Selectable calendar range, from today up to 14 days, per user.
- Web manifest, icons and a service worker, so the page can be installed as
  an app.
- Local task provider backed by SQLite, so the panel works on first login with
  nothing configured.

### Changed
- Integrations run inside the app instead of shelling out to CLIs installed on
  the host: IMAP/SMTP for email, iCal for calendars, REST for Jira and GitHub.
- Actions take effect immediately. They used to appear to do nothing until the
  next refresh cycle, which could be five minutes away.
- The session cookie moved from `SameSite=strict` to `lax`, without which the
  OAuth callback arrived with no session.
- Refresh interval dropped from 300 to 60 seconds.
- Subtasks are collapsed behind a disclosure arrow.

### Fixed
- Completing, editing and deleting a task worked again for Microsoft To Do.
  The id validation rejected `=`, which every Graph id carries, so every one
  of them failed with "id inválido".
- The task form's save button locks while the request is in flight; a second
  click used to create a duplicate task.
- Next.js upgraded to 16.3.3 for a critical advisory that included a
  middleware bypass — and middleware is this app's auth gate.
- Every open pull request in a tracked repository is listed. A filter was
  hiding the most common case in one's own repository: the dependabot PR.
- Removing a user now deletes their data as well; it used to leave encrypted
  credentials behind.
- Tests can no longer reach the real database.
- The notification popover no longer renders behind the next column.

## [0.1.0] - 2026-08-25

### Added
- First working version: email, calendar, pull requests, Jira, tasks,
  pomodoro and notifications on one page, behind a login.

[Unreleased]: https://github.com/joaosouzacoder/daily-web/compare/main...HEAD
