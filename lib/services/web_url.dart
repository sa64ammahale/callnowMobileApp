// DEPRECATED: Kept for backwards compatibility. Use ApiService and ConfigService instead.
import 'package:callnow_new/services/config_service.dart';

class Url {
  static String get baseUrl => ConfigService.baseUrl;

  @Deprecated('Use ApiService login()')
  static String get login => '$baseUrl/auth/login';
  
  @Deprecated('Use ApiService changePassword()')
  static String get changePswd => '$baseUrl/auth/change-password';
  
  @Deprecated('Use ApiService getCompanyList()')
  static String get companySearch => '$baseUrl/telecaller/companies';
  
  @Deprecated('Use ApiService getDashboardStats()')
  static String get splashScreen => '$baseUrl/telecaller/dashboard';
  
  @Deprecated('Use ApiService submitCallDirect()')
  static String get dialDataActivity => '$baseUrl/telecaller/submit_call.php';
  
  @Deprecated('Use ApiService getFreshData()')
  static String get newDataRequest => '$baseUrl/telecaller/fresh-data';
  
  @Deprecated('Use ApiService')
  static String get updateDataRequest => '$baseUrl/telecaller/update-data';
  
  @Deprecated('Use ApiService getCallHistory()')
  static String get myEnquiries => '$baseUrl/telecaller/calls';
  
  @Deprecated('Use ApiService')
  static String get updateEnquiry => '$baseUrl/telecaller/calls/update';
  
  @Deprecated('Use ApiService')
  static String get deleteEnquiry => '$baseUrl/telecaller/calls/delete';
  
  @Deprecated('Use ApiService')
  static String get addEnquiry => '$baseUrl/telecaller/calls/add';
  
  @Deprecated('Use ApiService getFreshData()')
  static String get getFreshData => '$baseUrl/telecaller/fresh-data';
}
