 /// <reference path="./client.d.ts" /> 
 import queryString from "query-string";


export function postApiV1SubmitTx(body: SubmitTxArgsDummy, fetchFn?: (input: RequestInfo, init?: RequestInit) => Promise<Response>): Promise<string> {
  let options: RequestInit = {
    credentials: "same-origin" as RequestCredentials,
    method: "POST",
    headers: {"Content-Type": "application/json;charset=utf-8"}
  };
  
  options.body = JSON.stringify(body);

  let params = {};
  return (fetchFn || window.fetch)(`/api/v1/submit_tx` + "?" + queryString.stringify(params), options).then((response) => {
    return new Promise((resolve, reject) => {
      if (response.status !== 200) {
        return response.text().then((text) => reject({text, status: response.status}));
      } else {
        return response.json().then((json) => resolve(json));
      }
    });
  });
}

export function getApiV1WalletByPublicKey(public_key: string, fetchFn?: (input: RequestInfo, init?: RequestInit) => Promise<Response>): Promise<WalletInfo> {
  let options: RequestInit = {
    credentials: "same-origin" as RequestCredentials,
    method: "GET",
    headers: {"Content-Type": "application/json;charset=utf-8"}
  };
  
  let params = {};
  return (fetchFn || window.fetch)(`/api/v1/wallet/${public_key}` + "?" + queryString.stringify(params), options).then((response) => {
    return new Promise((resolve, reject) => {
      if (response.status !== 200) {
        return response.text().then((text) => reject({text, status: response.status}));
      } else {
        return response.json().then((json) => resolve(json));
      }
    });
  });
}

export function postApiV1SendFunds(body: SendFundsRequest, fetchFn?: (input: RequestInfo, init?: RequestInit) => Promise<Response>): Promise<ApiTxDummy> {
  let options: RequestInit = {
    credentials: "same-origin" as RequestCredentials,
    method: "POST",
    headers: {"Content-Type": "application/json;charset=utf-8"}
  };
  
  options.body = JSON.stringify(body);

  let params = {};
  return (fetchFn || window.fetch)(`/api/v1/send_funds` + "?" + queryString.stringify(params), options).then((response) => {
    return new Promise((resolve, reject) => {
      if (response.status !== 200) {
        return response.text().then((text) => reject({text, status: response.status}));
      } else {
        return response.json().then((json) => resolve(json));
      }
    });
  });
}

export function postApiV1RawSign(body: RawSignArgs, fetchFn?: (input: RequestInfo, init?: RequestInit) => Promise<Response>): Promise<RawSignResponse> {
  let options: RequestInit = {
    credentials: "same-origin" as RequestCredentials,
    method: "POST",
    headers: {"Content-Type": "application/json;charset=utf-8"}
  };
  
  options.body = JSON.stringify(body);

  let params = {};
  return (fetchFn || window.fetch)(`/api/v1/raw_sign` + "?" + queryString.stringify(params), options).then((response) => {
    return new Promise((resolve, reject) => {
      if (response.status !== 200) {
        return response.text().then((text) => reject({text, status: response.status}));
      } else {
        return response.json().then((json) => resolve(json));
      }
    });
  });
}

export function getApiV1NetworkId(fetchFn?: (input: RequestInfo, init?: RequestInit) => Promise<Response>): Promise<NetworkIdResponse> {
  let options: RequestInit = {
    credentials: "same-origin" as RequestCredentials,
    method: "GET",
    headers: {"Content-Type": "application/json;charset=utf-8"}
  };
  
  let params = {};
  return (fetchFn || window.fetch)(`/api/v1/network_id` + "?" + queryString.stringify(params), options).then((response) => {
    return new Promise((resolve, reject) => {
      if (response.status !== 200) {
        return response.text().then((text) => reject({text, status: response.status}));
      } else {
        return response.json().then((json) => resolve(json));
      }
    });
  });
}

export function getApiV1Healthcheck(fetchFn?: (input: RequestInfo, init?: RequestInit) => Promise<Response>): Promise<{}> {
  let options: RequestInit = {
    credentials: "same-origin" as RequestCredentials,
    method: "GET",
    headers: {"Content-Type": "application/json;charset=utf-8"}
  };
  
  let params = {};
  return (fetchFn || window.fetch)(`/api/v1/healthcheck` + "?" + queryString.stringify(params), options).then((response) => {
    return new Promise((resolve, reject) => {
      if (response.status !== 200) {
        return response.text().then((text) => reject({text, status: response.status}));
      } else {
        return response.json().then((json) => resolve(json));
      }
    });
  });
}