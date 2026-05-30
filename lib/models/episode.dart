class Episode {
  final String name;
  final String url;
  final String imageUrl;
  final String overview;

  const Episode({required this.name, required this.url, this.imageUrl = '', this.overview = ''});

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'imageUrl': imageUrl,
        'overview': overview,
      };

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        imageUrl: json['imageUrl'] as String? ?? '',
        overview: json['overview'] as String? ?? '',
      );
}
