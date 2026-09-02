import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/stock.dart';
import '../models/stock_trend.dart';
import '../services/api_service.dart';
import 'models/challenge.dart';

class LearnerApi {
  static String get _base => ApiService.baseUrl;

  static Future<List<InvChallengeSummary>> listChallenges() async {
    final response = await http.get(
      Uri.parse('$_base/inv-challenges'),
      headers: ApiService.requestHeaders(),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return ApiService.decodeJsonList(response.body)
          .map((e) => InvChallengeSummary.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    throw Exception(ApiService.responseError(response, 'Failed to load challenges'));
  }

  static Future<InvChallengeDetail> createChallenge({
    required String name,
    required double initialNetworth,
    required int durationDays,
    required List<InvRosterDraft> members,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/inv-challenges'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode({
        'name': name,
        'initial_networth': initialNetworth,
        'duration_days': durationDays,
        'members': members.map((m) => m.toJson()).toList(),
      }),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 201) {
      return InvChallengeDetail.fromJson(json.decode(response.body));
    }
    throw Exception(ApiService.responseError(response, 'Failed to create challenge'));
  }

  static Future<InvChallengeDetail> getChallenge(int id) async {
    final response = await http.get(
      Uri.parse('$_base/inv-challenges/$id'),
      headers: ApiService.requestHeaders(),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return InvChallengeDetail.fromJson(json.decode(response.body));
    }
    throw Exception(ApiService.responseError(response, 'Failed to load challenge'));
  }

  static Future<InvChallengeDetail> joinChallenge(String inviteCode) async {
    final response = await http.post(
      Uri.parse('$_base/inv-challenges/join'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode({'invite_code': inviteCode}),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return InvChallengeDetail.fromJson(json.decode(response.body));
    }
    throw Exception(ApiService.responseError(response, 'Failed to join challenge'));
  }

  static Future<Map<String, dynamic>> lookupUser(String identifier) async {
    final response = await http.get(
      Uri.parse('$_base/inv-challenges/lookup-user')
          .replace(queryParameters: {'identifier': identifier}),
      headers: ApiService.requestHeaders(),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception(ApiService.responseError(response, 'User not found'));
  }

  static Future<InvChallengeDetail> addMember(int id, InvRosterDraft member) async {
    final response = await http.post(
      Uri.parse('$_base/inv-challenges/$id/members'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode(member.toJson()),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return InvChallengeDetail.fromJson(json.decode(response.body));
    }
    throw Exception(ApiService.responseError(response, 'Failed to add member'));
  }

  static Future<InvChallengeDetail> removeMember(int id, int memberId) async {
    final response = await http.delete(
      Uri.parse('$_base/inv-challenges/$id/members/$memberId'),
      headers: ApiService.requestHeaders(),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return InvChallengeDetail.fromJson(json.decode(response.body));
    }
    throw Exception(ApiService.responseError(response, 'Failed to remove member'));
  }

  static Future<List<InvLeaderboardRow>> leaderboard(int id) async {
    final response = await http.get(
      Uri.parse('$_base/inv-challenges/$id/leaderboard'),
      headers: ApiService.requestHeaders(),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return ApiService.decodeJsonList(response.body)
          .map((e) => InvLeaderboardRow.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    throw Exception(ApiService.responseError(response, 'Failed to load leaderboard'));
  }

  static Future<List<Stock>> holdings(int id) async {
    final response = await http.get(
      Uri.parse('$_base/inv-challenges/$id/holdings'),
      headers: ApiService.requestHeaders(),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return ApiService.decodeJsonList(response.body)
          .map((e) => Stock.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    throw Exception(ApiService.responseError(response, 'Failed to load holdings'));
  }

  static Future<List<StockTrend>> trends(int id) async {
    final response = await http.get(
      Uri.parse('$_base/inv-challenges/$id/trends'),
      headers: ApiService.requestHeaders(),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return ApiService.decodeJsonList(response.body)
          .map((e) => StockTrend.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    throw Exception(ApiService.responseError(response, 'Failed to load trends'));
  }

  static Future<InvChallengePortfolio> portfolio(int id) async {
    final response = await http.get(
      Uri.parse('$_base/inv-challenges/$id/portfolio'),
      headers: ApiService.requestHeaders(),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return InvChallengePortfolio.fromJson(json.decode(response.body));
    }
    throw Exception(ApiService.responseError(response, 'Failed to load portfolio'));
  }

  static Future<void> buy(int id, {required String symbol, required double quantity}) async {
    final response = await http.post(
      Uri.parse('$_base/inv-challenges/$id/buy'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode({'symbol': symbol, 'quantity': quantity}),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 201) return;
    throw Exception(ApiService.responseError(response, 'Buy failed'));
  }

  static Future<void> sell(int id, {required String symbol, required double quantity}) async {
    final response = await http.post(
      Uri.parse('$_base/inv-challenges/$id/sell'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode({'symbol': symbol, 'quantity': quantity}),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 201) return;
    throw Exception(ApiService.responseError(response, 'Sell failed'));
  }

  static Future<List<Map<String, dynamic>>> transactions(int id, {String? symbol}) async {
    var uri = Uri.parse('$_base/inv-challenges/$id/transactions');
    if (symbol != null && symbol.isNotEmpty) {
      uri = uri.replace(queryParameters: {'symbol': symbol});
    }
    final response = await http.get(uri, headers: ApiService.requestHeaders());
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return ApiService.decodeJsonList(response.body).cast<Map<String, dynamic>>();
    }
    throw Exception(ApiService.responseError(response, 'Failed to load transactions'));
  }

  static Future<void> hold(int challengeId, int stockId) async {
    final response = await http.post(
      Uri.parse('$_base/inv-challenges/$challengeId/holdings/$stockId/hold'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode({}),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) return;
    throw Exception(ApiService.responseError(response, 'Hold failed'));
  }

  static Future<void> setThresholds(
    int challengeId,
    int stockId, {
    required double setBuyPrice,
    required double setProfitBookingPrice,
    required double setStopLossPrice,
  }) async {
    final response = await http.put(
      Uri.parse('$_base/inv-challenges/$challengeId/holdings/$stockId/thresholds'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode({
        'set_buy_price': setBuyPrice,
        'set_profit_booking_price': setProfitBookingPrice,
        'set_stop_loss_price': setStopLossPrice,
      }),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) return;
    throw Exception(ApiService.responseError(response, 'Failed to save thresholds'));
  }

  static Future<void> setNotes(int challengeId, int stockId, String notes) async {
    final response = await http.put(
      Uri.parse('$_base/inv-challenges/$challengeId/holdings/$stockId/notes'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode({'notes': notes}),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) return;
    throw Exception(ApiService.responseError(response, 'Failed to save notes'));
  }

  static Future<void> clearReviewValues(
    int challengeId,
    int stockId,
    List<String> fields,
  ) async {
    final response = await http.post(
      Uri.parse(
          '$_base/inv-challenges/$challengeId/holdings/$stockId/clear-review-values'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode({'fields': fields}),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) return;
    throw Exception(ApiService.responseError(response, 'Failed to clear values'));
  }

  static Future<void> clearAllReviewValues(int challengeId, List<String> fields) async {
    final response = await http.post(
      Uri.parse('$_base/inv-challenges/$challengeId/clear-review-values'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode({'fields': fields}),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) return;
    throw Exception(ApiService.responseError(response, 'Failed to clear values'));
  }

  static Future<List<Stock>> refreshPrices(int id) async {
    final response = await http.post(
      Uri.parse('$_base/inv-challenges/$id/refresh-prices'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode({}),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return ApiService.decodeJsonList(response.body)
          .map((e) => Stock.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    throw Exception(ApiService.responseError(response, 'Failed to refresh prices'));
  }
}
