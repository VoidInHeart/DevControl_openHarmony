/** Maps gateway NetStack error codes to actionable messages. */
export function describeHttpBusinessError(code: number): string {
  if (code === 2300028) {
    return '无法连接网关：连接超时，请检查局域网地址和网关状态';
  }
  if (code === 2300060) {
    return '证书校验失败：请确认网关地址与证书 SAN 匹配，且证书由内置项目 CA 签发';
  }
  if (code === 2300006) {
    return '无法解析网关地址，请检查 HTTPS 地址格式';
  }
  return '网络请求失败（错误码 ' + code.toString() + '）';
}
