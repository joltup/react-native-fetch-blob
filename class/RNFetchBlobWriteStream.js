// Copyright 2016 wkh237@github. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import {
 NativeModules,
 DeviceEventEmitter,
 NativeAppEventEmitter,
} from 'react-native'

const RNFetchBlob = NativeModules.RNFetchBlob

export default class RNFetchBlobWriteStream {

  id : string;
  encoding : string;
  append : boolean;

  constructor(streamId:string, encoding:string, append:boolean) {
    this.id = streamId
    this.encoding = encoding
    this.append = append
  }

  write(data:string): Promise<RNFetchBlobWriteStream> {
    return new Promise((resolve, reject) => {
      try {
        let method = this.encoding === 'ascii' ? 'writeArrayChunk' : 'writeChunk'
        if(this.encoding.toLocaleLowerCase() === 'ascii' && !Array.isArray(data)) {
            reject(new Error('ascii input data must be an Array'))
            return
        }
        RNFetchBlob[method](this.id, data, (error) => {
          if(error)
            reject(new Error(error))
          else
            resolve(this)
        })
      } catch(err) {
        reject(new Error(err))
      }
    })
  }

  close() {
    return new Promise((resolve, reject) => {
      try {
        RNFetchBlob.closeStream(this.id, () => {
          resolve()
        })
      } catch (err) {
        reject(new Error(err))
      }
    })
  }

}
