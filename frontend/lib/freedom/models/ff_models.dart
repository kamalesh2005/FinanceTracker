class FFRetireSimRow {
  final int year;
  final double corpus;
  final double passiveIncome;
  final double passivePct;
  final double activeIncome;
  final double totalExpenses;
  final double flagExpenses;
  final double oneTimeExpense;
  final double endIncome;
  final bool incomeMeetsExpense;
  final bool ready;

  FFRetireSimRow({
    required this.year,
    required this.corpus,
    required this.passiveIncome,
    required this.passivePct,
    required this.activeIncome,
    required this.totalExpenses,
    required this.flagExpenses,
    required this.oneTimeExpense,
    required this.endIncome,
    required this.incomeMeetsExpense,
    required this.ready,
  });

  factory FFRetireSimRow.fromJson(Map<String, dynamic> json) {
    return FFRetireSimRow(
      year: _asInt(json['year']) ?? 0,
      corpus: _asDouble(json['corpus']) ?? 0,
      passiveIncome: _asDouble(json['passive_income']) ?? 0,
      passivePct: _asDouble(json['passive_pct']) ?? 0,
      activeIncome: _asDouble(json['active_income']) ?? 0,
      totalExpenses: _asDouble(json['total_expenses']) ?? 0,
      flagExpenses: _asDouble(json['flag_expenses']) ?? 0,
      oneTimeExpense: _asDouble(json['one_time_expense']) ?? 0,
      endIncome: _asDouble(json['end_income']) ?? 0,
      incomeMeetsExpense: json['income_meets_expense'] == true,
      ready: json['ready'] == true,
    );
  }
}

class FFLiveWellYearRow {
  final int year;
  final double endIncome;
  final double totalExpenses;
  final double savings;
  final double passivePct;
  final double todaySavings;

  FFLiveWellYearRow({
    required this.year,
    required this.endIncome,
    required this.totalExpenses,
    required this.savings,
    this.passivePct = 0,
    this.todaySavings = 0,
  });

  factory FFLiveWellYearRow.fromJson(Map<String, dynamic> json) {
    return FFLiveWellYearRow(
      year: _asInt(json['year']) ?? 0,
      endIncome: _asDouble(json['end_income']) ?? 0,
      totalExpenses: _asDouble(json['total_expenses']) ?? 0,
      savings: _asDouble(json['savings']) ?? 0,
      passivePct: _asDouble(json['passive_pct']) ?? 0,
      todaySavings: _asDouble(json['today_savings']) ?? 0,
    );
  }
}

class FFLiveWellDetail {
  final String scenario;
  final String scenarioLabel;
  final double amount;
  final int targetYear;
  final int lastOneTimeYear;
  final double totalSavings;
  final double todaySurplus;
  final double passivePct;
  final int discountYears;
  final List<FFLiveWellYearRow> yearRows;
  final String? message;

  FFLiveWellDetail({
    required this.scenario,
    required this.scenarioLabel,
    required this.amount,
    this.targetYear = 0,
    this.lastOneTimeYear = 0,
    this.totalSavings = 0,
    this.todaySurplus = 0,
    this.passivePct = 0,
    this.discountYears = 0,
    this.yearRows = const [],
    this.message,
  });

  factory FFLiveWellDetail.fromJson(Map<String, dynamic> json) {
    List<FFLiveWellYearRow> rows = const [];
    final raw = json['year_rows'];
    if (raw is List) {
      rows = raw
          .whereType<Map>()
          .map((e) => FFLiveWellYearRow.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return FFLiveWellDetail(
      scenario: (json['scenario'] ?? '').toString(),
      scenarioLabel: (json['scenario_label'] ?? '').toString(),
      amount: _asDouble(json['amount']) ?? 0,
      targetYear: _asInt(json['target_year']) ?? 0,
      lastOneTimeYear: _asInt(json['last_one_time_year']) ?? 0,
      totalSavings: _asDouble(json['total_savings']) ?? 0,
      todaySurplus: _asDouble(json['today_surplus']) ?? 0,
      passivePct: _asDouble(json['passive_pct']) ?? 0,
      discountYears: _asInt(json['discount_years']) ?? 0,
      yearRows: rows,
      message: json['message']?.toString(),
    );
  }
}

class FFMetrics {
  final double activeIncome;
  final double passiveIncome;
  final double regularExpenses;
  final int? retirementYear;
  final int? yearsToRetire;
  final double? annualEnjoymentFund;
  final double? liquidityForBreakMonths;
  final double termInsuranceNeed;
  final int currentYear;

  FFMetrics({
    required this.activeIncome,
    required this.passiveIncome,
    required this.regularExpenses,
    this.retirementYear,
    this.yearsToRetire,
    this.annualEnjoymentFund,
    this.liquidityForBreakMonths,
    required this.termInsuranceNeed,
    required this.currentYear,
  });

  factory FFMetrics.fromJson(Map<String, dynamic> json) {
    return FFMetrics(
      activeIncome: _asDouble(json['active_income']) ?? 0,
      passiveIncome: _asDouble(json['passive_income']) ?? 0,
      regularExpenses: _asDouble(json['regular_expenses']) ?? 0,
      retirementYear: _asInt(json['retirement_year']),
      yearsToRetire: _asInt(json['years_to_retire']),
      annualEnjoymentFund: _asDouble(json['annual_enjoyment_fund']),
      liquidityForBreakMonths: _asDouble(json['liquidity_for_break_months']),
      termInsuranceNeed: _asDouble(json['term_insurance_need']) ?? 0,
      currentYear: _asInt(json['current_year']) ?? DateTime.now().year,
    );
  }
}

class FFAsset {
  final int id;
  final String category;
  final String? presetKey;
  final String name;
  final double value;
  final bool isLiquid;
  final double linkedLiability;
  final double emiAmount;
  final int emiInstallmentsLeft;
  final double incomePct;
  final int incomeStartYear;
  final int? incomeEndYear;
  final double taxPct;
  final double calculatedIncome;
  final double effectiveIncome;

  FFAsset({
    required this.id,
    required this.category,
    this.presetKey,
    required this.name,
    required this.value,
    required this.isLiquid,
    required this.linkedLiability,
    required this.emiAmount,
    required this.emiInstallmentsLeft,
    required this.incomePct,
    required this.incomeStartYear,
    this.incomeEndYear,
    required this.taxPct,
    required this.calculatedIncome,
    required this.effectiveIncome,
  });

  factory FFAsset.fromJson(Map<String, dynamic> json) {
    return FFAsset(
      id: _asInt(json['id']) ?? 0,
      category: (json['category'] ?? FFAssetCategory.liquidCash).toString(),
      presetKey: json['preset_key']?.toString(),
      name: (json['name'] ?? '').toString(),
      value: _asDouble(json['value']) ?? 0,
      isLiquid: json['is_liquid'] == true,
      linkedLiability: _asDouble(json['linked_liability']) ?? 0,
      emiAmount: _asDouble(json['emi_amount']) ?? 0,
      emiInstallmentsLeft: _asInt(json['emi_installments_left']) ?? 0,
      incomePct: _asDouble(json['income_pct']) ?? 0,
      incomeStartYear: _asInt(json['income_start_year']) ?? 0,
      incomeEndYear: _asInt(json['income_end_year']),
      taxPct: _asDouble(json['tax_pct']) ?? 0,
      calculatedIncome: _asDouble(json['calculated_income']) ?? 0,
      effectiveIncome: _asDouble(json['effective_income']) ?? 0,
    );
  }
}

class FFAssetCategory {
  static const liquidCash = 'liquid_cash';
  static const marketEquity = 'market_equity';
  static const pfBonds = 'pf_bonds';
  static const realEstateGold = 'real_estate_gold';

  static const labels = <String, String>{
    liquidCash: 'Liquid & Cash Assets',
    marketEquity: 'Market & Equity Investments',
    pfBonds: 'Provident Funds & Bonds',
    realEstateGold: 'Real Estate & Gold',
  };

  static const order = <String>[
    liquidCash,
    marketEquity,
    pfBonds,
    realEstateGold,
  ];
}

class FFAssetPreset {
  final String key;
  final String category;
  final String name;
  final double incomePct;
  final bool isLiquid;
  final bool allowsEmi;
  /// Value is filled from main-portal Stocks / Mutual Funds on each summary load.
  final bool fromPortfolio;

  const FFAssetPreset({
    required this.key,
    required this.category,
    required this.name,
    required this.incomePct,
    required this.isLiquid,
    this.allowsEmi = false,
    this.fromPortfolio = false,
  });
}

const List<FFAssetPreset> ffAssetPresets = [
  FFAssetPreset(
    key: 'savings_bank',
    category: FFAssetCategory.liquidCash,
    name: 'Savings Bank Accounts',
    incomePct: 2.5,
    isLiquid: true,
  ),
  FFAssetPreset(
    key: 'fd',
    category: FFAssetCategory.liquidCash,
    name: 'Fixed Deposits (FDs)',
    incomePct: 6,
    isLiquid: true,
  ),
  FFAssetPreset(
    key: 'rd',
    category: FFAssetCategory.liquidCash,
    name: 'Recurring Deposits (RDs)',
    incomePct: 6,
    isLiquid: true,
  ),
  FFAssetPreset(
    key: 'liquid_mf',
    category: FFAssetCategory.liquidCash,
    name: 'Instant-redemption Liquid Mutual Funds',
    incomePct: 6,
    isLiquid: true,
  ),
  FFAssetPreset(
    key: 'stocks_domestic',
    category: FFAssetCategory.marketEquity,
    name: 'Direct Stocks — Domestic',
    incomePct: 12,
    isLiquid: false,
    fromPortfolio: true,
  ),
  FFAssetPreset(
    key: 'stocks_international',
    category: FFAssetCategory.marketEquity,
    name: 'Direct Stocks — International',
    incomePct: 12,
    isLiquid: false,
  ),
  FFAssetPreset(
    key: 'mutual_funds',
    category: FFAssetCategory.marketEquity,
    name: 'Mutual Funds',
    incomePct: 12,
    isLiquid: false,
    fromPortfolio: true,
  ),
  FFAssetPreset(
    key: 'etf_index',
    category: FFAssetCategory.marketEquity,
    name: 'ETFs + Index Funds',
    incomePct: 12,
    isLiquid: false,
    fromPortfolio: true,
  ),
  FFAssetPreset(
    key: 'epf_ppf',
    category: FFAssetCategory.pfBonds,
    name: 'Employee Provident Fund (EPF) + Public Provident Fund (PPF)',
    incomePct: 8,
    isLiquid: false,
  ),
  FFAssetPreset(
    key: 'nps',
    category: FFAssetCategory.pfBonds,
    name: 'National Pension System (NPS)',
    incomePct: 8,
    isLiquid: false,
  ),
  FFAssetPreset(
    key: 'govt_bonds',
    category: FFAssetCategory.pfBonds,
    name: 'Government & Infrastructure Bond',
    incomePct: 8,
    isLiquid: false,
  ),
  FFAssetPreset(
    key: 'primary_residence',
    category: FFAssetCategory.realEstateGold,
    name: 'Primary Residence',
    incomePct: 0,
    isLiquid: false,
    allowsEmi: true,
  ),
  FFAssetPreset(
    key: 'commercial_property',
    category: FFAssetCategory.realEstateGold,
    name: 'Commercial/Residential Properties',
    incomePct: 2.5,
    isLiquid: false,
    allowsEmi: true,
  ),
  FFAssetPreset(
    key: 'physical_gold',
    category: FFAssetCategory.realEstateGold,
    name: 'Physical Gold',
    incomePct: 6,
    isLiquid: false,
  ),
  FFAssetPreset(
    key: 'digital_gold',
    category: FFAssetCategory.realEstateGold,
    name: 'Digital Gold',
    incomePct: 0,
    isLiquid: false,
    fromPortfolio: true,
  ),
  FFAssetPreset(
    key: 'sgb',
    category: FFAssetCategory.realEstateGold,
    name: 'Sovereign Gold Bonds (SGBs)',
    incomePct: 8,
    isLiquid: false,
    fromPortfolio: true,
  ),
];

List<FFAssetPreset> ffPresetsForCategory(String category) =>
    ffAssetPresets.where((p) => p.category == category).toList();

FFAssetPreset? ffPresetByKey(String key) {
  for (final p in ffAssetPresets) {
    if (p.key == key) return p;
  }
  return null;
}

bool ffAssetAllowsEmi(String? presetKey, {String? category}) {
  if (presetKey != null) {
    final p = ffPresetByKey(presetKey);
    if (p != null) return p.allowsEmi;
  }
  return false;
}

List<FFAsset> ffAssetsForPreset(List<FFAsset> assets, String presetKey) {
  return assets.where((a) => a.presetKey == presetKey).toList();
}

FFAsset? ffAssetForPreset(List<FFAsset> assets, String presetKey) {
  final list = ffAssetsForPreset(assets, presetKey);
  return list.isEmpty ? null : list.first;
}

List<FFAsset> ffCustomAssetsForCategory(List<FFAsset> assets, String category) {
  return assets
      .where((a) =>
          a.category == category && (a.presetKey == null || a.presetKey!.isEmpty))
      .toList();
}

class FFAssetPresetSummary {
  final double totalValue;
  final double incomePct;
  final double totalCalculatedIncome;
  final double totalEmi;
  final int maxMonthsLeft;
  final int count;

  const FFAssetPresetSummary({
    required this.totalValue,
    required this.incomePct,
    required this.totalCalculatedIncome,
    required this.totalEmi,
    required this.maxMonthsLeft,
    required this.count,
  });

  factory FFAssetPresetSummary.fromAssets(
    List<FFAsset> rows, {
    required double defaultIncomePct,
  }) {
    if (rows.isEmpty) {
      return FFAssetPresetSummary(
        totalValue: 0,
        incomePct: defaultIncomePct,
        totalCalculatedIncome: 0,
        totalEmi: 0,
        maxMonthsLeft: 0,
        count: 0,
      );
    }
    var value = 0.0;
    var income = 0.0;
    var emi = 0.0;
    var maxLeft = 0;
    for (final a in rows) {
      value += a.value;
      income += a.calculatedIncome;
      emi += a.emiAmount;
      if (a.emiInstallmentsLeft > maxLeft) maxLeft = a.emiInstallmentsLeft;
    }
    return FFAssetPresetSummary(
      totalValue: value,
      incomePct: rows.first.incomePct,
      totalCalculatedIncome: income,
      totalEmi: emi,
      maxMonthsLeft: maxLeft,
      count: rows.length,
    );
  }
}

class FFJobIncome {
  final int id;
  final String? presetKey;
  final String label;
  final double amount;
  final int endYear;
  final int? startYear;

  FFJobIncome({
    required this.id,
    this.presetKey,
    required this.label,
    required this.amount,
    required this.endYear,
    this.startYear,
  });

  factory FFJobIncome.fromJson(Map<String, dynamic> json) {
    return FFJobIncome(
      id: _asInt(json['id']) ?? 0,
      presetKey: json['preset_key']?.toString(),
      label: (json['label'] ?? 'Salary').toString(),
      amount: _asDouble(json['amount']) ?? 0,
      endYear: _asInt(json['end_year']) ?? 0,
      startYear: _asInt(json['start_year']),
    );
  }
}

const String ffJobPensionPresetKey = 'pension';

class FFJobPreset {
  final String key;
  final String label;

  const FFJobPreset({required this.key, required this.label});
}

const FFJobPreset ffJobPensionPreset = FFJobPreset(
  key: ffJobPensionPresetKey,
  label: 'Pension',
);

const List<FFJobPreset> ffJobPresets = [
  FFJobPreset(key: 'primary_salary', label: 'Primary Salary'),
  FFJobPreset(key: 'profession', label: 'Profession / Business'),
  FFJobPreset(key: 'bonus', label: 'Bonus / Variable Pay'),
];

bool ffIsJobPension(FFJobIncome row) => row.presetKey == ffJobPensionPresetKey;

int? ffJobDisplayEndYear(FFJobIncome? job) {
  final y = job?.endYear ?? 0;
  return y > 0 ? y : null;
}

FFJobIncome? ffJobForPreset(List<FFJobIncome> rows, String presetKey) {
  for (final r in rows) {
    if (r.presetKey == presetKey) return r;
  }
  return null;
}

List<FFJobIncome> ffCustomJobIncome(List<FFJobIncome> rows) {
  final keys = {
    ...ffJobPresets.map((p) => p.key),
    ffJobPensionPresetKey,
  };
  return rows
      .where((r) =>
          r.presetKey == null ||
          r.presetKey!.isEmpty ||
          !keys.contains(r.presetKey))
      .toList();
}

class FFExpense {
  final int id;
  final String? presetKey;
  final String category;
  final double amount;
  final int? endYear;

  FFExpense({
    required this.id,
    this.presetKey,
    required this.category,
    required this.amount,
    this.endYear,
  });

  factory FFExpense.fromJson(Map<String, dynamic> json) {
    return FFExpense(
      id: _asInt(json['id']) ?? 0,
      presetKey: json['preset_key']?.toString(),
      category: (json['category'] ?? '').toString(),
      amount: _asDouble(json['amount']) ?? 0,
      endYear: _asInt(json['end_year']),
    );
  }
}

class FFExpensePreset {
  final String key;
  final String category;
  final String label;

  const FFExpensePreset({
    required this.key,
    required this.category,
    required this.label,
  });
}

const List<FFExpensePreset> ffExpensePresets = [
  FFExpensePreset(key: 'rent', category: 'rent', label: 'Rent+Maintenance'),
  FFExpensePreset(key: 'house_help', category: 'house_help', label: 'House Help'),
  FFExpensePreset(
    key: 'utilities',
    category: 'utilities',
    label: 'Grocery / Electricity / Gas / Mobile / Broadband',
  ),
  FFExpensePreset(
    key: 'clothes_entertainment',
    category: 'clothes_entertainment',
    label: 'Clothes & Entertainment',
  ),
  FFExpensePreset(
    key: 'petrol_travel',
    category: 'petrol_travel',
    label: 'Petrol/Travel',
  ),
  FFExpensePreset(
    key: 'medicine_health',
    category: 'medicine_health',
    label: 'Medicine/Health',
  ),
  FFExpensePreset(key: 'education', category: 'education', label: 'Education'),
  FFExpensePreset(key: 'vacation', category: 'vacation', label: 'Vacation'),
  FFExpensePreset(key: 'misc', category: 'misc', label: 'Misc.'),
  FFExpensePreset(
    key: 'insurance_payment',
    category: 'insurance_payment',
    label: 'Insurance Payment',
  ),
  FFExpensePreset(
    key: 'emi',
    category: 'emi',
    label: 'EMI (not linked to Asset) e.g. Education Loan',
  ),
];

FFExpense? ffExpenseForPreset(List<FFExpense> rows, String presetKey) {
  for (final r in rows) {
    if (r.presetKey == presetKey) return r;
  }
  // Legacy rows saved before preset_key existed.
  for (final r in rows) {
    if ((r.presetKey == null || r.presetKey!.isEmpty) &&
        r.category == presetKey) {
      return r;
    }
  }
  return null;
}

List<FFExpense> ffCustomExpenses(List<FFExpense> rows) {
  return rows.where((r) => !ffIsPresetExpense(r)).toList();
}

bool ffIsPresetExpense(FFExpense row) {
  if (row.presetKey != null && row.presetKey!.isNotEmpty) {
    return true;
  }
  return ffExpenseCategoryLabels.containsKey(row.category);
}

class FFOneTimeExpense {
  final int id;
  final String? presetKey;
  final String name;
  final double amount;
  final int expectedYear;

  FFOneTimeExpense({
    required this.id,
    this.presetKey,
    required this.name,
    required this.amount,
    required this.expectedYear,
  });

  factory FFOneTimeExpense.fromJson(Map<String, dynamic> json) {
    return FFOneTimeExpense(
      id: _asInt(json['id']) ?? 0,
      presetKey: json['preset_key']?.toString(),
      name: (json['name'] ?? '').toString(),
      amount: _asDouble(json['amount']) ?? 0,
      expectedYear: _asInt(json['expected_year']) ?? 0,
    );
  }
}

class FFOneTimePreset {
  final String key;
  final String name;

  const FFOneTimePreset({required this.key, required this.name});
}

const List<FFOneTimePreset> ffOneTimePresets = [
  FFOneTimePreset(key: 'international_education', name: 'International Education'),
  FFOneTimePreset(key: 'marriage', name: 'Marriage'),
  FFOneTimePreset(key: 'home_purchase', name: 'Home Purchase'),
  FFOneTimePreset(key: 'vehicle_purchase', name: 'Vehicle Purchase'),
];

FFOneTimeExpense? ffOneTimeForPreset(List<FFOneTimeExpense> rows, String presetKey) {
  for (final r in rows) {
    if (r.presetKey == presetKey) return r;
  }
  return null;
}

List<FFOneTimeExpense> ffCustomOneTimeExpenses(List<FFOneTimeExpense> rows) {
  final presetKeys = ffOneTimePresets.map((p) => p.key).toSet();
  return rows
      .where((r) => r.presetKey == null ||
          r.presetKey!.isEmpty ||
          !presetKeys.contains(r.presetKey))
      .toList();
}

class FFSummary {
  final List<FFAsset> assets;
  final List<FFJobIncome> jobIncome;
  final List<FFExpense> expenses;
  final List<FFOneTimeExpense> oneTimeExpenses;
  final FFMetrics metrics;
  final List<FFRetireSimRow> retireSimulation;
  final FFLiveWellDetail liveWellDetail;

  FFSummary({
    required this.assets,
    required this.jobIncome,
    required this.expenses,
    required this.oneTimeExpenses,
    required this.metrics,
    required this.retireSimulation,
    required this.liveWellDetail,
  });

  factory FFSummary.fromJson(Map<String, dynamic> json) {
    List<T> mapList<T>(String key, T Function(Map<String, dynamic>) parse) {
      final raw = json[key];
      if (raw is! List) return <T>[];
      return raw
          .whereType<Map>()
          .map((e) => parse(Map<String, dynamic>.from(e)))
          .toList();
    }

    return FFSummary(
      assets: mapList('assets', FFAsset.fromJson),
      jobIncome: mapList('job_income', FFJobIncome.fromJson),
      expenses: mapList('expenses', FFExpense.fromJson),
      oneTimeExpenses: mapList('one_time_expenses', FFOneTimeExpense.fromJson),
      metrics: FFMetrics.fromJson(
        Map<String, dynamic>.from(json['metrics'] as Map? ?? {}),
      ),
      retireSimulation: mapList(
        'retire_simulation',
        FFRetireSimRow.fromJson,
      ),
      liveWellDetail: FFLiveWellDetail.fromJson(
        Map<String, dynamic>.from(json['live_well_detail'] as Map? ?? {}),
      ),
    );
  }
}

const Map<String, String> ffExpenseCategoryLabels = {
  'rent': 'Rent+Maintenance',
  'house_help': 'House Help',
  'utilities': 'Grocery / Electricity / Gas / Mobile / Broadband',
  'clothes_entertainment': 'Clothes & Entertainment',
  'petrol_travel': 'Petrol/Travel',
  'medicine_health': 'Medicine/Health',
  'education': 'Education',
  'vacation': 'Vacation',
  'misc': 'Misc.',
  'insurance_payment': 'Insurance Payment',
  'emi': 'EMI (not linked to Asset) e.g. Education Loan',
};

bool ffExpenseShowsEndYear(String category) => category == 'emi';

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}
