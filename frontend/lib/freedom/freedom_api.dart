import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import 'models/ff_models.dart';

class FreedomApi {
  static String get _base => ApiService.baseUrl;

  static Future<FFSummary> getSummary() async {
    final response = await http.get(
      Uri.parse('$_base/ff/summary'),
      headers: ApiService.requestHeaders(),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return FFSummary.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception(
      ApiService.responseError(response, 'Failed to load Horizon summary'),
    );
  }

  static Future<FFAsset> createAsset(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$_base/ff/assets'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode(body),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 201) {
      return FFAsset.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception(ApiService.responseError(response, 'Failed to create asset'));
  }

  static Future<FFAsset> updateAsset(int id, Map<String, dynamic> body) async {
    final response = await http.put(
      Uri.parse('$_base/ff/assets/$id'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode(body),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return FFAsset.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception(ApiService.responseError(response, 'Failed to update asset'));
  }

  static Future<int> resetAssetIncomeDefaults() async {
    final response = await http.post(
      Uri.parse('$_base/ff/assets/reset-income-defaults'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: '{}',
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      final payload = json.decode(response.body) as Map<String, dynamic>;
      return (payload['updated'] as num?)?.toInt() ?? 0;
    }
    throw Exception(
      ApiService.responseError(response, 'Failed to reset asset return defaults'),
    );
  }

  static Future<void> deleteAsset(int id) async {
    final response = await http.delete(
      Uri.parse('$_base/ff/assets/$id'),
      headers: ApiService.requestHeaders(),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode != 204) {
      throw Exception(ApiService.responseError(response, 'Failed to delete asset'));
    }
  }

  static Future<FFJobIncome> createJobIncome(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$_base/ff/job-income'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode(body),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 201) {
      return FFJobIncome.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception(ApiService.responseError(response, 'Failed to create job income'));
  }

  static Future<FFJobIncome> updateJobIncome(int id, Map<String, dynamic> body) async {
    final response = await http.put(
      Uri.parse('$_base/ff/job-income/$id'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode(body),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return FFJobIncome.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception(ApiService.responseError(response, 'Failed to update job income'));
  }

  static Future<void> deleteJobIncome(int id) async {
    final response = await http.delete(
      Uri.parse('$_base/ff/job-income/$id'),
      headers: ApiService.requestHeaders(),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode != 204) {
      throw Exception(ApiService.responseError(response, 'Failed to delete job income'));
    }
  }

  static Future<FFExpense> createExpense(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$_base/ff/expenses'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode(body),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 201) {
      return FFExpense.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception(ApiService.responseError(response, 'Failed to create expense'));
  }

  static Future<FFExpense> updateExpense(int id, Map<String, dynamic> body) async {
    final response = await http.put(
      Uri.parse('$_base/ff/expenses/$id'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode(body),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return FFExpense.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception(ApiService.responseError(response, 'Failed to update expense'));
  }

  static Future<void> deleteExpense(int id) async {
    final response = await http.delete(
      Uri.parse('$_base/ff/expenses/$id'),
      headers: ApiService.requestHeaders(),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode != 204) {
      throw Exception(ApiService.responseError(response, 'Failed to delete expense'));
    }
  }

  static Future<FFOneTimeExpense> createOneTime(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$_base/ff/one-time-expenses'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode(body),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 201) {
      return FFOneTimeExpense.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception(
      ApiService.responseError(response, 'Failed to create one-time expense'),
    );
  }

  static Future<FFOneTimeExpense> updateOneTime(int id, Map<String, dynamic> body) async {
    final response = await http.put(
      Uri.parse('$_base/ff/one-time-expenses/$id'),
      headers: ApiService.requestHeaders(jsonBody: true),
      body: json.encode(body),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode == 200) {
      return FFOneTimeExpense.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception(
      ApiService.responseError(response, 'Failed to update one-time expense'),
    );
  }

  static Future<void> deleteOneTime(int id) async {
    final response = await http.delete(
      Uri.parse('$_base/ff/one-time-expenses/$id'),
      headers: ApiService.requestHeaders(),
    );
    ApiService.noteUnauthorized(response);
    if (response.statusCode != 204) {
      throw Exception(
        ApiService.responseError(response, 'Failed to delete one-time expense'),
      );
    }
  }
}
