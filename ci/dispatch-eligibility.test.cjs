const { test } = require('node:test');
const assert = require('node:assert/strict');
const { canDispatch } = require('./dispatch-eligibility.cjs');

test('dispatches only leaf issues whose native blockers are all closed', async () => {
  const graph = {
    2: { sub_issues: [3, 4], 'dependencies/blocked_by': [] },
    3: { sub_issues: [], 'dependencies/blocked_by': [] },
    4: { sub_issues: [], 'dependencies/blocked_by': [{ state: 'closed' }, { state: 'open' }] },
  };
  const paginate = async (route, { issue_number }) => {
    const relation = route.split('{issue_number}/')[1];
    return graph[issue_number][relation];
  };
  const repo = { owner: 'example', repo: 'health' };
  assert.equal(await canDispatch(paginate, repo, 2), false);
  assert.equal(await canDispatch(paginate, repo, 3), true);
  assert.equal(await canDispatch(paginate, repo, 4), false);
  graph[4]['dependencies/blocked_by'][1].state = 'closed';
  assert.equal(await canDispatch(paginate, repo, 4), true);
});
