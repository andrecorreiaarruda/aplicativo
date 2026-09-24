/// Quem emite a OS: a empresa no rodapé e o responsável técnico na
/// assinatura.
///
/// Fica no banco local deste computador, preenchido uma vez pelo menu da
/// conta. Não vai no código porque são dados de quem usa o aplicativo, e
/// mudam — um telefone novo não deveria exigir uma versão nova.
class ServiceOrderIssuer {
  const ServiceOrderIssuer({
    this.companyName = '',
    this.taxId = '',
    this.address = '',
    this.city = '',
    this.responsibleName = '',
    this.responsibleTitle = '',
    this.registration = '',
    this.phone = '',
    this.email = '',
  });

  /// Razão social ou nome fantasia, como deve sair no rodapé.
  final String companyName;

  /// CNPJ ou CPF.
  final String taxId;

  /// Endereço completo, numa linha.
  final String address;

  /// Cidade da assinatura: "Curitiba/PR".
  final String city;

  final String responsibleName;

  /// Formação, como "Engenheiro Eletricista".
  final String responsibleTitle;

  /// Registro profissional, como "CREA-PR 228325/D".
  final String registration;

  final String phone;
  final String email;

  static const empty = ServiceOrderIssuer();

  /// O mínimo para a OS ter quem a assine.
  bool get isComplete =>
      companyName.trim().isNotEmpty && responsibleName.trim().isNotEmpty;

  /// Primeira linha do rodapé: a empresa.
  String get companyLine => _join([
    companyName,
    if (taxId.trim().isNotEmpty) 'CNPJ ${taxId.trim()}',
    address,
  ], ' – ');

  /// Segunda linha do rodapé: o responsável e como falar com ele.
  String get responsibleLine {
    final qualification = _join([responsibleTitle, registration], ', ');
    final person = _join([responsibleName, qualification], ' — ');
    return _join([person, phone, email], ' – ');
  }

  /// Abaixo do nome, na assinatura.
  String get signatureCaption =>
      _join(['Responsável Técnico', registration], ' — ');

  ServiceOrderIssuer copyWith({
    String? companyName,
    String? taxId,
    String? address,
    String? city,
    String? responsibleName,
    String? responsibleTitle,
    String? registration,
    String? phone,
    String? email,
  }) => ServiceOrderIssuer(
    companyName: companyName ?? this.companyName,
    taxId: taxId ?? this.taxId,
    address: address ?? this.address,
    city: city ?? this.city,
    responsibleName: responsibleName ?? this.responsibleName,
    responsibleTitle: responsibleTitle ?? this.responsibleTitle,
    registration: registration ?? this.registration,
    phone: phone ?? this.phone,
    email: email ?? this.email,
  );

  Map<String, String> toJson() => {
    'companyName': companyName,
    'taxId': taxId,
    'address': address,
    'city': city,
    'responsibleName': responsibleName,
    'responsibleTitle': responsibleTitle,
    'registration': registration,
    'phone': phone,
    'email': email,
  };

  factory ServiceOrderIssuer.fromJson(Map<dynamic, dynamic> json) {
    String read(String key) => (json[key] as String? ?? '').trim();
    return ServiceOrderIssuer(
      companyName: read('companyName'),
      taxId: read('taxId'),
      address: read('address'),
      city: read('city'),
      responsibleName: read('responsibleName'),
      responsibleTitle: read('responsibleTitle'),
      registration: read('registration'),
      phone: read('phone'),
      email: read('email'),
    );
  }

  static String _join(List<String> parts, String separator) => parts
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .join(separator);
}
