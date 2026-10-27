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

  factory ClientDataModel.fromJson(Map<String, dynamic> json) =>
      ClientDataModel(
        id: json["ID"],
        name: json["NAME"],
        mobile: json["MOBILE"],
        company: json["COMPANY"],
        package: json["PACKAGE"],
        status: json["STATUS"],
        uploadDate: DateTime.parse(json["UPLOAD_DATE"]),
        callBy: json["CALL_BY"],
        callTime: DateTime.parse(json["CALL_TIME"]),
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
      };
}
