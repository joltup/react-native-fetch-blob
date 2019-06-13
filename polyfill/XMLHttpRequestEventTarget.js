// Copyright 2016 wkh237@github. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import EventTarget from './EventTarget.js'
import Log from '../utils/log.js'

const log = new Log('XMLHttpRequestEventTarget')

log.disable()
// log.level(3)

export default class XMLHttpRequestEventTarget extends EventTarget {

  _onabort : (e:Event) => void = () => {};
  _onerror : (e:Event) => void = () => {};
  _onload : (e:Event) => void = () => {};
  _onloadstart : (e:Event) => void = () => {};
  _onprogress : (e:Event) => void = () => {};
  _ontimeout : (e:Event) => void = () => {};
  _onloadend : (e:Event) => void = () => {};

  constructor() {
    super()
    log.info('constructor called')
  }

  dispatchEvent(event:string, e:Event) {
    log.debug('dispatch event', event, e)
    super.dispatchEvent(event, e)
    switch(event) {
      case 'abort' :
        this._onabort(e)
      break;
      case 'error' :
        this._onerror(e)
      break;
      case 'load' :
        this._onload(e)
      break;
      case 'loadstart' :
        this._onloadstart(e)
      break;
      case 'loadend' :
        this._onloadend(e)
      break;
      case 'progress' :
        this._onprogress(e)
      break;
      case 'timeout' :
        this._ontimeout(e)
      break;
    }
  }

  set onabort(fn:(e:Event) => void) {
    log.info('set onabort')
    this._onabort = fn
  }

  get onabort() {
    return this._onabort
  }
  set onerror(fn:(e:Event) => void) {
    log.info('set onerror')
    this._onerror = fn
  }

  get onerror() {
    return this._onerror
  }

  set onload(fn:(e:Event) => void) {
    log.info('set onload', fn)
    this._onload = fn
  }

  get onload() {
    return this._onload
  }

  set onloadstart(fn:(e:Event) => void) {
    log.info('set onloadstart')
    this._onloadstart = fn
  }

  get onloadstart() {
    return this._onloadstart
  }

  set onprogress(fn:(e:Event) => void) {
    log.info('set onprogress')
    this._onprogress = fn
  }

  get onprogress() {
    return this._onprogress
  }

  set ontimeout(fn:(e:Event) => void) {
    log.info('set ontimeout')
    this._ontimeout = fn
  }

  get ontimeout() {
    return this._ontimeout
  }

  set onloadend(fn:(e:Event) => void) {
    log.info('set onloadend')
    this._onloadend = fn
  }

  get onloadend() {
    return this._onloadend
  }

}
