/// Danh mục chọn Trường (`GET /api/v1/universities`): Cụm, quận (kèm Cụm) và mọi Trường.
class UniversityCatalog {
  const UniversityCatalog({required this.clusters, required this.districts, required this.universities});

  factory UniversityCatalog.fromJson(Map<String, dynamic> json) => UniversityCatalog(
        clusters: [for (final c in json['clusters'] as List) Cluster.fromJson(Map<String, dynamic>.from(c as Map))],
        districts: [for (final d in json['districts'] as List) District.fromJson(Map<String, dynamic>.from(d as Map))],
        universities: [
          for (final u in json['universities'] as List) UniversityOption.fromJson(Map<String, dynamic>.from(u as Map)),
        ],
      );

  final List<Cluster> clusters;
  final List<District> districts;
  final List<UniversityOption> universities;

  String clusterName(String? code) =>
      clusters.where((c) => c.code == code).map((c) => c.name).firstOrNull ?? 'Chưa rõ Cụm';

  String? clusterOfDistrict(String district) => districts.where((d) => d.name == district).firstOrNull?.clusterCode;
}

class Cluster {
  const Cluster({required this.code, required this.name});
  factory Cluster.fromJson(Map<String, dynamic> json) => Cluster(code: json['code'] as String, name: json['name'] as String);

  final String code;
  final String name;
}

class District {
  const District({required this.name, required this.clusterCode});
  factory District.fromJson(Map<String, dynamic> json) =>
      District(name: json['name'] as String, clusterCode: json['clusterCode'] as String);

  final String name;
  final String clusterCode;
}

/// Một Trường (cơ sở thi đấu) trong danh mục.
class UniversityOption {
  const UniversityOption({
    required this.id,
    required this.shortName,
    required this.name,
    required this.color,
    this.parentName,
    this.aliases,
    this.district,
    this.clusterCode,
    this.verified = true,
  });

  factory UniversityOption.fromJson(Map<String, dynamic> json) => UniversityOption(
        id: json['id'] as String,
        shortName: json['shortName'] as String,
        name: json['name'] as String,
        color: json['color'] as String? ?? '#9AA6A7',
        parentName: json['parentName'] as String?,
        aliases: json['aliases'] as String?,
        district: json['district'] as String?,
        clusterCode: json['clusterCode'] as String?,
        verified: json['verified'] as bool? ?? true,
      );

  final String id;
  final String shortName;
  final String name;
  final String color;
  final String? parentName;
  final String? aliases;
  final String? district;
  final String? clusterCode;

  /// false = Sinh viên tự thêm, admin chưa duyệt.
  final bool verified;

  String get _haystack => foldVietnamese([name, shortName, parentName, aliases, district].whereType<String>().join(' '));
}

const _accents = {
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'e': 'èéẹẻẽêềếệểễ',
  'i': 'ìíịỉĩ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'u': 'ùúụủũưừứựửữ',
  'y': 'ỳýỵỷỹ',
  'd': 'đ',
};
final _plain = {
  for (final e in _accents.entries)
    for (final ch in e.value.split('')) ch: e.key,
};
final _combining = RegExp('[̀-ͯ]');
final _spaces = RegExp(r'\s+');

/// Bỏ dấu tiếng Việt, chữ thường, gộp khoảng trắng; khớp foldVietnamese ở backend.
String foldVietnamese(String s) => s
    .toLowerCase()
    .replaceAll(_combining, '')
    .split('')
    .map((ch) => _plain[ch] ?? ch)
    .join()
    .replaceAll(_spaces, ' ')
    .trim();

/// Gợi ý Trường theo từ khoá (không dấu, mọi từ đều phải có): tên, tên ngắn, thương hiệu, từ khoá, quận.
/// Trường có tên ngắn bắt đầu bằng từ khoá lên trước.
List<UniversityOption> searchUniversities(List<UniversityOption> all, String query) {
  final words = foldVietnamese(query).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return all;
  final hits = all.where((u) => words.every(u._haystack.contains)).toList();
  final q = words.join(' ');
  int rank(UniversityOption u) => foldVietnamese(u.shortName).startsWith(q) ? 0 : 1;
  hits.sort((a, b) => rank(a).compareTo(rank(b)));
  return hits;
}
