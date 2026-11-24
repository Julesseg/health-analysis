async function canDispatch(paginate, repository, number) {
  const params = { ...repository, issue_number: number, per_page: 100 };
  const route = 'GET /repos/{owner}/{repo}/issues/{issue_number}';
  const children = await paginate(route + '/sub_issues', params);
  if (children.length) return false;

  const blockers = await paginate(route + '/dependencies/blocked_by', params);
  return blockers.every(issue => issue.state === 'closed');
}

module.exports = { canDispatch };
