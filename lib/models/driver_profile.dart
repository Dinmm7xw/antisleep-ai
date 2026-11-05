import 'dart:convert';

/// Model representing an authenticated driver profile in AntiSleep AI.
class DriverProfile {
  final String name;
  final String emailOrPhone;
  final String carPlate;
  final String language;
  final String sosPhone;
  final bool isGuest;

  const DriverProfile({
    required this.name,
    required this.emailOrPhone,
    required this.carPlate,
    this.language = 'kk',
    this.sosPhone = '',
    this.isGuest = false,
  });

  DriverProfile copyWith({
    String? name,
    String? emailOrPhone,
    String? carPlate,
    String? language,
    String? sosPhone,
    bool? isGuest,
  }) {
    return DriverProfile(
      name: name ?? this.name,
      emailOrPhone: emailOrPhone ?? this.emailOrPhone,
      carPlate: carPlate ?? this.carPlate,
      language: language ?? this.language,
      sosPhone: sosPhone ?? this.sosPhone,
      isGuest: isGuest ?? this.isGuest,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'emailOrPhone': emailOrPhone,
        'carPlate': carPlate,
        'language': language,
        'sosPhone': sosPhone,
        'isGuest': isGuest,
      };

  factory DriverProfile.fromJson(Map<String, dynamic> json) {
    return DriverProfile(
      name: json['name'] as String? ?? 'Жүргізуші / Водитель',
      emailOrPhone: json['emailOrPhone'] as String? ?? '',
      carPlate: json['carPlate'] as String? ?? 'KZ 000 AAA 01',
      language: json['language'] as String? ?? 'kk',
      sosPhone: json['sosPhone'] as String? ?? '',
      isGuest: json['isGuest'] as bool? ?? false,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static DriverProfile? fromJsonString(String source) {
    try {
      final dynamic decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) {
        return DriverProfile.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }
}

