import ballerina/http;
import ballerinax/salesforce;
import ballerinax/salesforce.soap;
import ballerina/jwt;
import ballerina/io;

// Create Salesforce client configuration by reading from environment.
configurable string clientId = ?;
configurable string clientSecret = ?;
configurable string refreshToken = ?;
configurable string refreshUrl = ?;
configurable string baseUrl = ?;

// Using direct-token config for client configuration
salesforce:ConnectionConfig config = {
    baseUrl,
    auth: {
        clientId,
        clientSecret,
        refreshToken,
        refreshUrl
    }
};

salesforce:Client baseClient = check new (config);
soap:Client soapClient = check new(config);

# A service representing a network-accessible API
# bound to port `9091`.
@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"]
    }
}
service / on new http:Listener(9092) {

    resource function get upgrade(http:Headers headers) returns Account|InternalServerErrorString|http:NotFound|error {

        [string, string]|error ownerInfo = getOwnerWithEmail(headers);
        if ownerInfo is error {
            return ownerInfo;
        }

        string owner;
        string email;
        [owner, email] = ownerInfo;

        io:println("Owner : ", owner);
        io:println("Email : ", email);

        string sampleQuery = string `SELECT AccountID FROM Contact WHERE Email = '${email}'`;
        stream<record {}, error?> queryResults = check baseClient->query(sampleQuery);
        
        int nLines = 0;
        string recordId = "";
        check from record {} rd in queryResults
            do {
                recordId = check rd.toJson().AccountId;
                nLines += 1;
            };

        if (nLines == 0) {
            return http:NOT_FOUND;
        }

        return {accountId: recordId, isUpgraded: true};
    }

    resource function post upgrade(http:Headers headers, @http:Payload LeadInfo payload) returns http:Created|http:NotFound|error {

        string|error owner = getOwner(headers);
        if owner is error {
            return owner;
        }
        
        io:println("Owner : ", owner);
        io:println("Email : ", payload.email);

        string sampleQuery = string `SELECT Id FROM Lead WHERE Email = '${payload.email ?: ""}'`;
        stream<record {}, error?> queryResults = check baseClient->query(sampleQuery);
        
        int nLines = 0;
        string recordId;
        check from record {} rd in queryResults
            do {
                recordId = check rd.toJson().Id;
                nLines += 1;
            };

        if (nLines == 0) {
            io:println("Lead not found for the email : ", payload.email);
            return http:NOT_FOUND;
        }
        
        io:println("Lead found for the email : ", payload.email);
        soap:ConvertedLead _ = check soapClient->convertLead({leadId: recordId, convertedStatus: "Closed - Converted"});
        io:println("Lead converted.");
        return http:CREATED;
    }
}

function getOwner(http:Headers headers) returns string|error {

    var jwtHeader = headers.getHeader("x-jwt-assertion");
    if jwtHeader is http:HeaderNotFoundError {
        var authHeader = headers.getHeader("Authorization");
        if authHeader is http:HeaderNotFoundError {
            return authHeader;
        } else {
            if (authHeader.startsWith("Bearer ")) {
                jwtHeader = authHeader.substring(7);
            }
        }
    }

    if (jwtHeader is http:HeaderNotFoundError) {
        return jwtHeader;
    }

    [jwt:Header, jwt:Payload] [_, payload] = check jwt:decode(jwtHeader);
    return getOwnerFromPayload(payload);
}

function getOwnerFromPayload(jwt:Payload payload) returns string {

    string? subClaim = payload.sub;
    if subClaim is () {
        subClaim = "Test_Key_User";
    }

    return <string>subClaim;
}

function getOwnerWithEmail(http:Headers headers) returns [string, string]|error {

    var jwtHeader = headers.getHeader("x-jwt-assertion");
    if jwtHeader is http:HeaderNotFoundError {
        var authHeader = headers.getHeader("Authorization");
        if authHeader is http:HeaderNotFoundError {
            return authHeader;
        } else {
            if (authHeader.startsWith("Bearer ")) {
                jwtHeader = authHeader.substring(7);
            }
        }
    }

    if (jwtHeader is http:HeaderNotFoundError) {
        return jwtHeader;
    }

    [jwt:Header, jwt:Payload] [_, payload] = check jwt:decode(jwtHeader);
    string owner = getOwnerFromPayload(payload);
    string emailAddress = payload["email"].toString();

    return [owner, emailAddress];
}