class Url {
  static const String baseUrl =
      "https://starsinfotech.in/callnow/FLUTTER_API.php?apicall=";

  static final String login = "${baseUrl}LOGIN";
  static final String changePswd = "${baseUrl}RESET_PASSWORD";
  static final String companySearch = "${baseUrl}COMPANY_LIST";
  static final String splashScreen = "${baseUrl}SPLASH_SCREEN";
  static final String dialDataActivity = "${baseUrl}DIAL_DATA_ACTIVITY";
  static final String newDataRequest = "${baseUrl}NEW_DATA_REQUEST";
  static final String updateDataRequest = "${baseUrl}USER_DATA_UPDATE";
  static final String myEnquiries = "${baseUrl}MY_ENQUIRIES";
  static final String updateEnquiry = "${baseUrl}UPDATE_ENQUIRY";
  static final String deleteEnquiry = "${baseUrl}DELETE_ENQUIRY";
  static final String addEnquiry = "${baseUrl}ADD_ENQUIRY";
  static final String getFreshData = "${baseUrl}GET_GOOGLE_SHEET_DATA";
}
