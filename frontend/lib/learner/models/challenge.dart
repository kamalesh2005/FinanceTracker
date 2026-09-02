class InvChallengeSummary {
  final int id;
  final String name;
  final double initialNetworth;
  final int durationDays;
  final DateTime startsAt;
  final DateTime endsAt;
  final String inviteCode;
  final bool isCreator;
  final bool ended;
  final int memberCount;
  final double myCash;
  final DateTime? createdAt;

  InvChallengeSummary({
    required this.id,
    required this.name,
    required this.initialNetworth,
    required this.durationDays,
    required this.startsAt,
    required this.endsAt,
    required this.inviteCode,
    required this.isCreator,
    required this.ended,
    required this.memberCount,
    required this.myCash,
    this.createdAt,
  });

  factory InvChallengeSummary.fromJson(Map<String, dynamic> json) {
    return InvChallengeSummary(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '',
      initialNetworth: _asDouble(json['initial_networth']),
      durationDays: _asInt(json['duration_days']),
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? '') ??
          DateTime.now(),
      endsAt: DateTime.tryParse(json['ends_at']?.toString() ?? '') ??
          DateTime.now(),
      inviteCode: json['invite_code']?.toString() ?? '',
      isCreator: json['is_creator'] == true,
      ended: json['ended'] == true,
      memberCount: _asInt(json['member_count']),
      myCash: _asDouble(json['my_cash']),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  Duration get remaining {
    final left = endsAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}

class InvChallengeMember {
  final int id;
  final int? userId;
  final String status;
  final String displayName;
  final double cashBalance;
  final String invitedEmail;
  final String invitedMobile;
  final DateTime? joinedAt;

  InvChallengeMember({
    required this.id,
    this.userId,
    required this.status,
    required this.displayName,
    required this.cashBalance,
    this.invitedEmail = '',
    this.invitedMobile = '',
    this.joinedAt,
  });

  factory InvChallengeMember.fromJson(Map<String, dynamic> json) {
    return InvChallengeMember(
      id: _asInt(json['id']),
      userId: json['user_id'] == null ? null : _asInt(json['user_id']),
      status: json['status']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      cashBalance: _asDouble(json['cash_balance']),
      invitedEmail: json['invited_email']?.toString() ?? '',
      invitedMobile: json['invited_mobile']?.toString() ?? '',
      joinedAt: DateTime.tryParse(json['joined_at']?.toString() ?? ''),
    );
  }

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
}

class InvChallengeDetail {
  final int id;
  final String name;
  final double initialNetworth;
  final int durationDays;
  final DateTime startsAt;
  final DateTime endsAt;
  final String inviteCode;
  final bool isCreator;
  final bool ended;
  final bool tradingOpen;
  final double myCash;
  final double myHoldingsValue;
  final double myNetworth;
  final List<InvChallengeMember> members;

  InvChallengeDetail({
    required this.id,
    required this.name,
    required this.initialNetworth,
    required this.durationDays,
    required this.startsAt,
    required this.endsAt,
    required this.inviteCode,
    required this.isCreator,
    required this.ended,
    required this.tradingOpen,
    required this.myCash,
    required this.myHoldingsValue,
    required this.myNetworth,
    required this.members,
  });

  factory InvChallengeDetail.fromJson(Map<String, dynamic> json) {
    final members = (json['members'] as List<dynamic>? ?? [])
        .map((e) => InvChallengeMember.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return InvChallengeDetail(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '',
      initialNetworth: _asDouble(json['initial_networth']),
      durationDays: _asInt(json['duration_days']),
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? '') ??
          DateTime.now(),
      endsAt: DateTime.tryParse(json['ends_at']?.toString() ?? '') ??
          DateTime.now(),
      inviteCode: json['invite_code']?.toString() ?? '',
      isCreator: json['is_creator'] == true,
      ended: json['ended'] == true,
      tradingOpen: json['trading_open'] == true,
      myCash: _asDouble(json['my_cash']),
      myHoldingsValue: _asDouble(json['my_holdings_value']),
      myNetworth: _asDouble(json['my_networth']),
      members: members,
    );
  }

  String get remainingLabel {
    if (ended) return 'Ended';
    final d = endsAt.difference(DateTime.now());
    if (d.inDays >= 1) return '${d.inDays}d left';
    if (d.inHours >= 1) return '${d.inHours}h left';
    return '${d.inMinutes}m left';
  }
}

class InvLeaderboardRow {
  final int rank;
  final int memberId;
  final int? userId;
  final String displayName;
  final double cash;
  final double holdingsValue;
  final double networth;
  final double profitLoss;
  final double profitLossPct;

  InvLeaderboardRow({
    required this.rank,
    required this.memberId,
    this.userId,
    required this.displayName,
    required this.cash,
    required this.holdingsValue,
    required this.networth,
    required this.profitLoss,
    required this.profitLossPct,
  });

  factory InvLeaderboardRow.fromJson(Map<String, dynamic> json) {
    return InvLeaderboardRow(
      rank: _asInt(json['rank']),
      memberId: _asInt(json['member_id']),
      userId: json['user_id'] == null ? null : _asInt(json['user_id']),
      displayName: json['display_name']?.toString() ?? '',
      cash: _asDouble(json['cash']),
      holdingsValue: _asDouble(json['holdings_value']),
      networth: _asDouble(json['networth']),
      profitLoss: _asDouble(json['profit_loss']),
      profitLossPct: _asDouble(json['profit_loss_pct']),
    );
  }
}

class InvChallengePortfolio {
  final double cash;
  final double invested;
  final double holdingsValue;
  final double networth;
  final double initialNetworth;
  final double profitLoss;
  final double profitLossPercentage;
  final double? xirr;
  final int holdingCount;

  InvChallengePortfolio({
    required this.cash,
    required this.invested,
    required this.holdingsValue,
    required this.networth,
    required this.initialNetworth,
    required this.profitLoss,
    required this.profitLossPercentage,
    this.xirr,
    required this.holdingCount,
  });

  factory InvChallengePortfolio.fromJson(Map<String, dynamic> json) {
    return InvChallengePortfolio(
      cash: _asDouble(json['cash']),
      invested: _asDouble(json['invested']),
      holdingsValue: _asDouble(json['holdings_value']),
      networth: _asDouble(json['networth']),
      initialNetworth: _asDouble(json['initial_networth']),
      profitLoss: _asDouble(json['profit_loss']),
      profitLossPercentage: _asDouble(json['profit_loss_percentage']),
      xirr: json['xirr'] == null ? null : _asDouble(json['xirr']),
      holdingCount: _asInt(json['holding_count']),
    );
  }
}

class InvRosterDraft {
  int? userId;
  String identifier;
  String displayName;
  String invitedEmail;
  String invitedMobile;

  InvRosterDraft({
    this.userId,
    this.identifier = '',
    this.displayName = '',
    this.invitedEmail = '',
    this.invitedMobile = '',
  });

  Map<String, dynamic> toJson() => {
        if (userId != null) 'user_id': userId,
        if (identifier.isNotEmpty) 'identifier': identifier,
        if (displayName.isNotEmpty) 'display_name': displayName,
        if (invitedEmail.isNotEmpty) 'invited_email': invitedEmail,
        if (invitedMobile.isNotEmpty) 'invited_mobile': invitedMobile,
      };

  String get label {
    if (displayName.isNotEmpty) return displayName;
    if (identifier.isNotEmpty) return identifier;
    if (invitedEmail.isNotEmpty) return invitedEmail;
    if (invitedMobile.isNotEmpty) return invitedMobile;
    return 'Pending invite';
  }
}

int _asInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _asDouble(dynamic value, [double fallback = 0.0]) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}
