const comparisonMetricLabels = {
  'YFSI_MEAN': '평균 금융 스트레스',
  'EXTERNAL_AREA_MEAN': '외부 부담 평균',
  'RESOURCE_DOMAIN_MEAN': '대응자원 평균',
  'PERCEIVED_STRESS_MEAN': '평균 체감 스트레스',
  'DEBT': '부채',
  'INCOME': '소득',
  'EMERGENCY_FUND': '비상자금',
  'FIXED_COST': '고정비',
  'FUTURE': '미래',
  'FAMILY': '가족부양',
  'FINANCIAL_LITERACY': '금융 이해력',
  'MONEY_MANAGEMENT': '재무 관리 역량',
  'SELF_EFFICACY': '금융 자기효능감',
};

String diagnosisBadgeName(Object? type) =>
    const {
      'DEBT': '부채부담형',
      'INCOME': '소득불안형',
      'EMERGENCY_FUND': '비상자금취약형',
      'FIXED_COST': '고정비압박형',
      'FUTURE': '미래불안형',
      'FAMILY': '부양부담형',
    }[type] ??
    '진단 유형 확인 중';
