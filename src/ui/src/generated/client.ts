 /// <reference path="./client.d.ts" /> 
 import queryString from "query-string";


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