// To parse this JSON data, do
//
//     final enquiryModel = enquiryModelFromJson(jsonString);

import 'dart:convert';

EnquiryModel enquiryModelFromJson(String str) =>
    EnquiryModel.fromJson(json.decode(str));

String enquiryModelToJson(EnquiryModel data) => json.encode(data.toJson());

class EnquiryModel {
  EnquiryModel({
    required this.id,
    required this.reqDate,
    required this.tsaId,
    required this.residenceType,
    required this.reqProduct,
    required this.clientName,
    required this.mobile,
    required this.company,
    required this.loanAmnt,
    required this.netSal,
    required this.salAcc,
    required this.remark,
    required this.enqStatus,
  });

  String id;
  String reqDate;
  String tsaId;
  String residenceType;
  String reqProduct;
  String clientName;
  String mobile;
  String company;
  String loanAmnt;
  String netSal;
  String salAcc;
  String remark;
  String enqStatus;

  factory EnquiryModel.fromJson(Map<String, dynamic> json) => EnquiryModel(
        id: json["ID"],
        reqDate: json["REQ_DATE"],
        tsaId: json["TSA_ID"],
        residenceType: json["RESIDENCE_TYPE"],
        reqProduct: json["REQ_PRODUCT"],
        clientName: json["CLIENT_NAME"],
        mobile: json["MOBILE"],
        company: json["COMPANY"],
        loanAmnt: json["LOAN_AMNT"],
        netSal: json["NET_SAL"],
        salAcc: json["SAL_ACC"],
        remark: json["REMARK"],
        enqStatus: json["ENQ_STATUS"],
      );

  Map<String, dynamic> toJson() => {
        "ID": id,
        "REQ_DATE": reqDate,
        "TSA_ID": tsaId,
        "RESIDENCE_TYPE": residenceType,
        "REQ_PRODUCT": reqProduct,
        "CLIENT_NAME": clientName,
        "MOBILE": mobile,
        "COMPANY": company,
        "LOAN_AMNT": loanAmnt,
        "NET_SAL": netSal,
        "SAL_ACC": salAcc,
        "REMARK": remark,
        "ENQ_STATUS": enqStatus,
      };
}
