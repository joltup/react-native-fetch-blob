import Oboe from 'oboe'
import URIUtil from './utils/uri'

const OboeExtended = (arg: string | Object) => {


  window.location = ''

  if(typeof arg === 'string') {
    if(URIUtil.isFileURI(arg)) {
      arg = {
        url : 'JSONStream://' + arg,
        headers : { noCache : true }
      }
    }
    else
      arg = 'JSONStream://' + arg

  }
  else if(typeof arg === 'object') {
    let headers = arg.headers || {}
    if(URIUtil.isFileURI(arg.url)) {
      headers.noCache = true
    }
    arg = Object.assign(arg, {
      url : 'JSONStream://' + arg.url,
      headers
    })
  }
  return Oboe(arg)
}

export default OboeExtended
