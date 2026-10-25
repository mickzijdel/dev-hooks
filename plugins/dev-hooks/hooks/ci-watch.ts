// CI watch: the pure half. register.tsx detects a push, resolves what was pushed and
// polls GitHub with these; nothing here touches `$`, so tests import it directly.

// ci-watch-reminder.sh's rule, kept line-local: `git` (env-prefixed or flagged) walking
// tokens to a `push` subcommand. `git push`, `git -C dir push`, `… && git push`; not
// `git config …pushurl`, `git switch`, `git pushall`.
const GIT_PUSH = /(^|[^A-Za-z0-9_])git([ \t]+\S+)*[ \t]+push([^A-Za-z0-9_]|$)/m

export const isGitPush = (command: string): boolean => GIT_PUSH.test(command)

// A dry run prints the same ref lines but triggers no run, so a watch would only
// find the last real push's run.
export const isDryRun = (command: string): boolean =>
  /(^|[^A-Za-z0-9_])git([ \t]+\S+)*[ \t]+push([ \t]+[^\s;&|]+)*[ \t]+(--dry-run|-n)([ \t;&|]|$)/m.test(command)

// A quiet push prints no ref lines, so it is the one push watched without them.
export const isQuietPush = (command: string): boolean =>
  /(^|[^A-Za-z0-9_])git([ \t]+\S+)*[ \t]+push([ \t]+[^\s;&|]+)*[ \t]+(-q|--quiet)([ \t;&|]|$)/m.test(command)

const unquote = (s: string) => s.replace(/^(['"])(.*)\1$/, '$2')

const resolveDir = (dir: string, cwd: string) => {
  const d = unquote(dir)
  return d.startsWith('/') ? d : `${cwd.replace(/\/$/, '')}/${d}`
}

// The directory a git subcommand ran in: `git -C <dir> <sub>`, a `cd <dir> &&` before it,
// or cwd.
export const gitDir = (command: string, cwd: string, sub: string): string => {
  const flag = new RegExp(
    String.raw`(^|[^A-Za-z0-9_])git[ \t]+(?:\S+[ \t]+)*?-C[ \t]+("[^"]*"|'[^']*'|\S+)(?:[ \t]+\S+)*?[ \t]+${sub}`,
    'm',
  ).exec(command)
  if (flag?.[2]) return resolveDir(flag[2], cwd)
  const cd = new RegExp(
    String.raw`(^|[;&|][ \t]*)cd[ \t]+("[^"]*"|'[^']*'|\S+)[ \t]*(&&|;)[^\n]*git([ \t]+\S+)*[ \t]+${sub}`,
    'm',
  ).exec(command)
  if (cd?.[2]) return resolveDir(cd[2], cwd)
  return cwd
}

export const pushDir = (command: string, cwd: string): string => gitDir(command, cwd, 'push')

// Options of `git push` that take the next word as their value.
const VALUE_OPTIONS = new Set(['-o', '--push-option', '--receive-pack', '--exec'])

// The words after each `push` subcommand, up to the end of that shell command.
const PUSH_ARGS = /(?:^|[^A-Za-z0-9_])git(?:[ \t]+\S+)*?[ \t]+push(?=$|[\s;&|()])((?:[ \t]+[^\s;&|()]+)*)/gm

// The repository each `git push` in the command names (its first word that is not an
// option or a redirect), or null for a bare push, which goes to the branch's push remote.
export const pushRepositories = (command: string): (string | null)[] => {
  const repos = [...command.matchAll(PUSH_ARGS)].map(m => {
    const words = (m[1] ?? '').split(/[ \t]+/).filter(w => w && !/^\d*[<>]/.test(w)).map(unquote)
    for (let i = 0; i < words.length; i++) {
      const word = words[i] ?? ''
      if (word === '--') return words[i + 1] ?? null
      if (VALUE_OPTIONS.has(word)) i++
      else if (!word.startsWith('-')) return word
    }
    return null
  })
  return repos.length > 0 ? repos : [null]
}

export type PushedRef = { src: string; dst: string; sha?: string }
// One per `To` line. Refs printed before any `To` line (cut off, as by `| tail -1`)
// come without a remote.
export type PushSection = { remote?: string; refs: PushedRef[] }

// git push's human output (stderr, which the Bash tool's result carries):
//   To github.com:owner/repo.git
//      762caa3..abc1234  main -> main
//    + 1111111...2222222 main -> main (forced update)
//    * [new branch]      feat -> feat
// A deletion (` - [deleted]`) and a rejection (` ! [rejected]`) start no run.
export const parsePushOutput = (text: string): PushSection[] => {
  const sections: PushSection[] = []
  let section: PushSection | undefined
  const add = (ref: PushedRef) => {
    if (!section) sections.push((section = { refs: [] }))
    section.refs.push(ref)
  }
  for (const line of text.split('\n')) {
    const to = /^To (\S+)/.exec(line)
    if (to?.[1]) {
      sections.push((section = { remote: to[1], refs: [] }))
      continue
    }
    const updated = /^\s*[+ ]?\s*[0-9a-f]{7,40}\.\.\.?([0-9a-f]{7,40})\s+(\S+)\s+->\s+(\S+)/.exec(line)
    if (updated?.[1] && updated[2] && updated[3]) {
      add({ sha: updated[1], src: updated[2], dst: updated[3] })
      continue
    }
    const created = /^\s*\*\s+\[new (?:branch|tag|reference)\]\s+(\S+)\s+->\s+(\S+)/.exec(line)
    if (created?.[1] && created[2]) add({ src: created[1], dst: created[2] })
  }
  return sections
}

// owner/repo of a GitHub remote URL in any spelling git accepts (scp-like, ssh://,
// https:// with or without credentials); null for any other host.
export const githubRepo = (url: string): string | null => {
  const m = /(?:^|[@/])github\.com[:/]+([^/\s:]+)\/([^/\s]+?)(?:\.git)?\/?$/.exec(url.trim())
  return m?.[1] && m[2] ? `${m[1]}/${m[2]}` : null
}

export type Run = {
  databaseId: number
  workflowName: string
  status: string
  conclusion: string
  headSha: string
  url: string
  event: string
}

export const RUN_FIELDS = 'databaseId,workflowName,status,conclusion,headSha,url,event'

export const parseRuns = (stdout: string): Run[] => {
  try {
    const rows = JSON.parse(stdout) as unknown
    return Array.isArray(rows) ? (rows as Run[]) : []
  } catch {
    return []
  }
}

export type Verdict = 'none' | 'pending' | 'success' | 'failure' | 'cancelled'

const FAILED = new Set(['failure', 'timed_out', 'startup_failure', 'action_required'])

// Runs are selected by head sha, never by recency: the newest run in the list can
// belong to an older push still running.
export const ciVerdict = (runs: Run[], sha: string): { verdict: Verdict; runs: Run[] } => {
  const mine = runs.filter(r => r.headSha === sha)
  if (mine.length === 0) return { verdict: 'none', runs: mine }
  if (mine.some(r => r.status !== 'completed')) return { verdict: 'pending', runs: mine }
  if (mine.some(r => FAILED.has(r.conclusion))) return { verdict: 'failure', runs: mine }
  if (mine.some(r => r.conclusion === 'cancelled')) return { verdict: 'cancelled', runs: mine }
  return { verdict: 'success', runs: mine }
}

export type Watch = { repo: string; sha: string; done: number; total: number }

const short = (sha: string) => sha.slice(0, 7)
const name = (repo: string) => repo.slice(repo.indexOf('/') + 1)

export const ciStatusLine = (watches: Watch[]): string | undefined => {
  if (watches.length === 0) return undefined
  const parts = watches.map(w =>
    w.total === 0
      ? `${name(w.repo)}@${short(w.sha)} waiting for its run`
      : `${name(w.repo)}@${short(w.sha)} ${w.done}/${w.total} runs done`,
  )
  return `CI: ${parts.join(' · ')}`
}

const runLine = (r: Run) => `- ${r.workflowName}: ${r.conclusion || r.status} (${r.event}) ${r.url}`

export const ciToast = (repo: string, sha: string, verdict: Verdict, runs: Run[]): string => {
  const where = `${name(repo)}@${short(sha)}`
  const bad = runs.filter(r => FAILED.has(r.conclusion)).map(r => r.workflowName)
  switch (verdict) {
    case 'success':
      return `✓ CI passed · ${where}`
    case 'failure':
      return `✗ CI failed · ${where}: ${bad.join(', ')}`
    case 'cancelled':
      return `◌ CI cancelled · ${where}`
    case 'none':
      return `? No CI run appeared · ${where}`
    default:
      return `… CI still running · ${where}`
  }
}

// What the model reads. A failure arrives as a prompt of its own, so it says what to do.
export const ciNote = (repo: string, sha: string, verdict: Verdict, runs: Run[], error?: string): string => {
  const head = `[dev-hooks CI watch] ${repo}@${short(sha)}`
  const lines = runs.map(runLine)
  switch (verdict) {
    case 'success':
      return [`${head}: CI passed.`, ...lines].join('\n')
    case 'failure': {
      const failed = runs.find(r => FAILED.has(r.conclusion))
      return [
        `${head}: CI FAILED on the commit you pushed.`,
        ...lines,
        `Find the cause (\`gh run view ${failed?.databaseId ?? '<id>'} --repo ${repo} --log-failed\`), fix it, and push the fix.`,
      ].join('\n')
    }
    case 'cancelled':
      return [`${head}: CI was cancelled (often a newer push superseded it).`, ...lines].join('\n')
    case 'none':
      return error
        ? `${head}: couldn't read its GitHub Actions runs (${error}). Watch it yourself: \`gh run list --repo ${repo} --commit ${sha}\`.`
        : `${head}: no GitHub Actions run appeared for this commit; its workflows may not trigger on this ref. Check \`gh run list --repo ${repo}\` if you expected one.`
    default:
      return [`${head}: CI is still running; the watch gave up waiting.`, ...lines].join('\n')
  }
}

// Read with the push's own tool result, so Claude doesn't start a watch of its own.
export const watchingNote = (targets: { repo: string; sha: string }[]): string =>
  `[dev-hooks CI watch] Watching the GitHub Actions run(s) for ${targets
    .map(t => `${t.repo}@${short(t.sha)}`)
    .join(', ')} in the background. Don't run \`gh run watch\` or poll for it: a failure comes back to you as a new message, and a pass is noted in the conversation.`
