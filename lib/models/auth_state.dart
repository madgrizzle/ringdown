enum AuthStatus { unknown, needsServer, needsLogin, authenticated }

class AuthState {
  const AuthState({
    required this.status,
    this.serverUrl,
    this.token,
    this.username,
    this.inboxEmail,
    this.lastUsername,
  });

  final AuthStatus status;
  final String? serverUrl;
  final String? token;
  final String? username;
  final String? inboxEmail;
  final String? lastUsername;

  static const unknown = AuthState(status: AuthStatus.unknown);

  AuthState copyWith({
    AuthStatus? status,
    String? serverUrl,
    String? token,
    String? username,
    String? inboxEmail,
    String? lastUsername,
    bool clearToken = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      serverUrl: serverUrl ?? this.serverUrl,
      token: clearToken ? null : (token ?? this.token),
      username: username ?? this.username,
      inboxEmail: inboxEmail ?? this.inboxEmail,
      lastUsername: lastUsername ?? this.lastUsername,
    );
  }
}

class Me {
  const Me({required this.username, required this.inboxEmail});

  final String username;
  final String inboxEmail;

  factory Me.fromJson(Map<String, dynamic> json) {
    return Me(
      username: json['username'] as String? ?? '',
      inboxEmail: json['inbox_email'] as String? ?? '',
    );
  }
}
