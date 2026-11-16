// To parse this JSON data, do
//
//     final clientDataModel = clientDataModelFromJson(jsonString);

import 'dart:convert';

ClientDataModel clientDataModelFromJson(String str) =>
    ClientDataModel.fromJson(json.decode(str));

String clientDataModelToJson(ClientDataModel data) =>
    json.encode(data.toJson());

class ClientDataModel {
  ClientDataModel({
    required this.id,
    required this.name,
    required this.mobile,
    required this.company,
    required this.package,
    required this.status,
    required this.uploadDate,
    required this.callBy,
    required this.callTime,
    this.otherInfo = '',
  });

  String id;
  String name;
  String mobile;
  String company;
  String package;
  String status;
  DateTime uploadDate;
  String callBy;
  DateTime callTime;
  String otherInfo;

  factory ClientDataModel.fromJson(Map<String, dynamic> json) =>
      ClientDataModel(
        id: (json["ID"] ?? json["id"] ?? '').toString(),
        name: (json["NAME"] ?? json["name"] ?? '').toString(),
        mobile: (json["MOBILE"] ?? json["mobile"] ?? '').toString(),
        company: (json["COMPANY"] ?? json["company"] ?? '').toString(),
        package: (json["PACKAGE"] ?? json["package"] ?? '').toString(),
        status: (json["STATUS"] ?? json["status"] ?? '').toString(),
        uploadDate: json["UPLOAD_DATE"] != null
            ? (DateTime.tryParse(json["UPLOAD_DATE"].toString()) ?? DateTime.now())
            : (json["upload_time"] != null
                ? (DateTime.tryParse(json["upload_time"].toString()) ?? DateTime.now())
                : DateTime.now()),
        callBy: (json["CALL_BY"] ?? json["call_by"] ?? '').toString(),
        callTime: json["CALL_TIME"] != null
            ? (DateTime.tryParse(json["CALL_TIME"].toString()) ?? DateTime.now())
            : DateTime.now(),
        otherInfo: (json["OTHER_INFO"] ??
                json["other_info"] ??
                json["CUST_OTHER_INFO"] ??
                json["MAINDATABASE_OTHER_INFO"] ??
                json["notes"] ??
                '')
            .toString(),
      );

  Map<String, dynamic> toJson() => {
        "ID": id,
        "NAME": name,
        "MOBILE": mobile,
        "COMPANY": company,
        "PACKAGE": package,
        "STATUS": status,
        "UPLOAD_DATE":
            "${uploadDate.year.toString().padLeft(4, '0')}-${uploadDate.month.toString().padLeft(2, '0')}-${uploadDate.day.toString().padLeft(2, '0')}",
        "CALL_BY": callBy,
        "CALL_TIME": callTime.toIso8601String(),
        "OTHER_INFO": otherInfo,
        "other_info": otherInfo,
      };
}
