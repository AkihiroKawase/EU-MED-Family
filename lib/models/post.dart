// lib/models/post.dart
class Post {
  final String id;        // Notionのpage_id
  final String title;
  final String pdfUrl;
  final String comment;
  final List<String> hashtags;

  Post({
    required this.id,
    required this.title,
    required this.pdfUrl,
    required this.comment,
    required this.hashtags,
  });
}