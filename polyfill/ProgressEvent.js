// Copyright 2016 wkh237@github. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Event from './Event'

export default class ProgressEvent extends Event {

  _lengthComputable : boolean = false;
  _loaded : number = -1;
  _total : numver = -1;

  constructor(lengthComputable, loaded, total) {
    super()
    this._lengthComputable = lengthComputable;
    this._loaded = loaded
    this._total = total
  }

  get lengthComputable() {
    return this._lengthComputable
  }

  get loaded() {
    return this._loaded
  }

  get total() {
    return this._total
  }

}
