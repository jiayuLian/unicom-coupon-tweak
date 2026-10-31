// inject.js —— couponhook.m 内联注入的同一份 JS 的可读副本
// 变量 T/C/A 由 dylib 编译时从 couponhook.m 顶部三个常量填充, 此处仅作说明
// 真机行为完全由 couponhook.m 内联版本决定, 改 .m 顶部常量即可, 不用动这里

(function(){
  var T = "__TARGET_PHONE__";   // kTargetPhone
  var C = "__TARGET_CITY__";    // kTargetCity
  var A = "__TARGET_AES__";     // kTargetPhoneAes

  // 改 URL query 里某个参数
  function setP(u, k, v){
    try{
      var x = u.split('?');
      if(x.length < 2) return u;
      var p = new URLSearchParams(x[1]);
      p.set(k, v);
      return x[0] + '?' + p.toString();
    }catch(e){ return u; }
  }

  // 改写逻辑: 查券用目标号, 下单校验 phoneNo+cityCode 改目标号, 且有密文时改 currentPhoneNumberAes
  function rw(u){
    if(u.indexOf('getNineGrid.action') > -1){
      u = setP(u, 'commonBean.phoneNo', T);
      u = setP(u, 'commonBean.cityCode', C);
    }
    if(u.indexOf('mobAppPayFeeCheck') > -1 || u.indexOf('mobAppPayFeeApply') > -1){
      u = setP(u, 'commonBean.phoneNo', T);
      u = setP(u, 'commonBean.cityCode', C);
      if(A.indexOf('__FILL') === -1){
        u = setP(u, 'custom.currentPhoneNumberAes', A);
      }
    }
    return u;
  }

  // hook fetch
  var of = window.fetch;
  window.fetch = function(i, o){
    var u = (typeof i === 'string') ? i : (i && i.url);
    if(u && (u.indexOf('getNineGrid') > -1 ||
             u.indexOf('mobAppPayFeeCheck') > -1 ||
             u.indexOf('mobAppPayFeeApply') > -1)){
      var n = rw(u);
      if(typeof i === 'string') i = n;
      else if(i && i.url) Object.defineProperty(i, 'url', {value:n, configurable:true});
    }
    return of.apply(this, arguments);
  };

  // hook XHR
  var oo = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(m, u){
    if(u && (u.indexOf('getNineGrid') > -1 ||
             u.indexOf('mobAppPayFeeCheck') > -1 ||
             u.indexOf('mobAppPayFeeApply') > -1)){
      u = rw(u);
    }
    return oo.call(this, m, u);
  };

  console.log('[coupon_hook] target=' + T);
})();
