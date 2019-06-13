// Copyright 2016 wkh237@github. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Log from '../utils/log.js'

const log = new Log('EventTarget')

log.disable()

export default class EventTarget {

  listeners : any;

  constructor() {
    log.info('constructor called')
    this.listeners = {}
  }

  /**
   * Add an event listener to given event type
   * @param {string} type Event type string
   * @param {(Event) => void} cb   Event handler function
   */
  addEventListener(type:string, cb : () => void) {
    log.info('add event listener', type, cb)
    if(!(type in this.listeners)) {
      this.listeners[type] = []
    }
    this.listeners[type].push(cb)
  }

  /**
   * Remove an event listener
   * @param  {string} type Type of the event listener
   * @param  {()=>void} cb Event listener function.
   * @return {[type]}             [description]
   */
  removeEventListener(type:string, cb:() => void) {
    log.info('remove event listener', type, cb)
    if(!(type in this.listeners))
      return
    let handlers = this.listeners[type]
    for(let i in handlers) {
      if(cb === handlers[i]) {
        handlers.splice(i,1)
        return this.removeEventListener(type, cb)
      }
    }
  }

  /**
   * Dispatch an event
   * @param {string} type Event type.
   * @param {Event} event Event data payload.
   */
  dispatchEvent(type:string,event:Event) {
    log.info('dispatch event', event)
    if(!(type in this.listeners))
      return
    let handlers = this.listeners[type]
    for(let i in handlers) {
      handlers[i].call(this, event)
    }

  }

  /**
   * Remove all registered listeners from this object.
   * @nonstandard
   * @return {[type]} [description]
   */
  clearEventListeners() {
    for(let i in this.listeners) {
      delete this.listeners[i]
    }
  }

}