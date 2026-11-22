const assert = require('node:assert/strict');
const test = require('node:test');
const { dispatchReadyIssues } = require('./dispatch-ready-issues.cjs');

async function dispatchedIssues({ issues, blockers = {}, children = {} }) {
  const dispatched = [];
  const listIssues = () => {};
  await dispatchReadyIssues({
    context: {
      repo: { owner: 'owner', repo: 'repo' },
      payload: { repository: { default_branch: 'master' } },
    },
    core: { info() {}, notice() {}, warning() {} },
    github: {
      async paginate(route, { labels, issue_number }) {
        switch (route) {
          case listIssues:
            return labels === 'ready-for-agent' ? issues : [];
          case 'GET /repos/{owner}/{repo}/issues/{issue_number}/dependencies/blocked_by':
            return blockers[issue_number] || [];
          case 'GET /repos/{owner}/{repo}/issues/{issue_number}/sub_issues':
            return children[issue_number] || [];
          default:
            throw new Error(`Unexpected route: ${route}`);
        }
      },
      rest: {
        issues: {
          listForRepo: listIssues,
          async getLabel() {},
          async createComment() {},
        },
        actions: {
          async createWorkflowDispatch({ ref, inputs }) {
            assert.equal(ref, 'master');
            dispatched.push(Number(inputs.issue));
          },
          async listWorkflowRuns() {
            return {
              data: {
                workflow_runs: dispatched.map(number => ({
                  display_title: `Agent implement: issue #${number}`,
                  created_at: new Date().toISOString(),
                  status: 'queued',
                })),
              },
            };
          },
        },
      },
    },
  });
  return dispatched;
}

test('only dispatches the child whose native blockers are all closed', async () => {
  const dispatched = await dispatchedIssues({
    issues: [
      { number: 4, title: 'Log a daily quantity', body: 'No blocker listed in the body' },
      { number: 8, title: 'Read resting heart rate', body: 'No blocker listed in the body' },
    ],
    blockers: {
      4: [{ number: 3, state: 'closed' }, { number: 5, state: 'open' }],
      8: [{ number: 3, state: 'closed' }],
    },
  });

  assert.deepEqual(dispatched, [8]);
});

test('skips an unblocked specification with native sub-issues', async () => {
  const dispatched = await dispatchedIssues({
    issues: [
      { number: 2, title: 'Personal health analysis app specification' },
      { number: 3, title: 'Bootstrap the app' },
    ],
    children: { 2: [{ number: 3, state: 'closed' }] },
  });

  assert.deepEqual(dispatched, [3]);
});
