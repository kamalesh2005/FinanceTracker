import 'package:flutter/foundation.dart';
import '../models/stock.dart';
import '../models/stock_trend.dart';
import 'learner_api.dart';
import 'models/challenge.dart';

class LearnerProvider extends ChangeNotifier {
  List<InvChallengeSummary> _challenges = [];
  InvChallengeDetail? _detail;
  InvChallengePortfolio? _portfolio;
  List<InvLeaderboardRow> _leaderboard = [];
  List<Stock> _holdings = [];
  List<StockTrend> _trends = [];
  bool _loading = false;
  String? _error;

  List<InvChallengeSummary> get challenges => _challenges;
  InvChallengeDetail? get detail => _detail;
  InvChallengePortfolio? get portfolio => _portfolio;
  List<InvLeaderboardRow> get leaderboard => _leaderboard;
  List<Stock> get holdings => _holdings;
  List<StockTrend> get trends => _trends;
  bool get isLoading => _loading;
  String? get error => _error;

  StockTrend? trendFor(int stockId) {
    for (final t in _trends) {
      if (t.stockId == stockId) return t;
    }
    return null;
  }

  void clear() {
    _challenges = [];
    _detail = null;
    _portfolio = null;
    _leaderboard = [];
    _holdings = [];
    _trends = [];
    _error = null;
    notifyListeners();
  }

  Future<void> loadChallenges() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _challenges = await LearnerApi.listChallenges();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> openChallenge(int id) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _detail = await LearnerApi.getChallenge(id);
      await _reloadChallengeData(id);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _reloadChallengeData(int id) async {
    final results = await Future.wait([
      LearnerApi.portfolio(id),
      LearnerApi.leaderboard(id),
      LearnerApi.holdings(id),
      LearnerApi.trends(id),
    ]);
    _portfolio = results[0] as InvChallengePortfolio;
    _leaderboard = results[1] as List<InvLeaderboardRow>;
    _holdings = results[2] as List<Stock>;
    _trends = results[3] as List<StockTrend>;
  }

  Future<void> refreshOpenChallenge() async {
    final id = _detail?.id;
    if (id == null) return;
    await openChallenge(id);
  }

  Future<InvChallengeDetail> createChallenge({
    required String name,
    required double initialNetworth,
    required int durationDays,
    required List<InvRosterDraft> members,
  }) async {
    final created = await LearnerApi.createChallenge(
      name: name,
      initialNetworth: initialNetworth,
      durationDays: durationDays,
      members: members,
    );
    await loadChallenges();
    return created;
  }

  Future<InvChallengeDetail> join(String code) async {
    final joined = await LearnerApi.joinChallenge(code);
    await loadChallenges();
    return joined;
  }
}
