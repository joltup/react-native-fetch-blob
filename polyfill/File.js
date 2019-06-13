// Copyright 2016 wkh237@github. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Blob from './Blob.js'

export default class File extends Blob {

  name : string = '';

  static build(name:string, data:any, cType:string):Promise<File> {
    return new Promise((resolve, reject) => {
      if (data === undefined) {
        reject(new TypeError('data is undefined'))
      }
      new File(data, cType).onCreated((f) => {
        f.name = name
        resolve(f)
      })
    })
  }

  constructor(data:any , cType:string) {
    super(data, cType)
  }

}
