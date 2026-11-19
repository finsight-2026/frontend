String newsArticleImagePath(String id, String edition, int revision) => Uri(
  path: '/api/v1/news/$id/image',
  queryParameters: {'edition': edition, 'revision': revision.toString()},
).toString();
