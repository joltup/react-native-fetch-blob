package com.RNFetchBlob.Response;

import com.RNFetchBlob.RNFetchBlobConst;
import com.RNFetchBlob.RNFetchBlobProgressConfig;
import com.RNFetchBlob.RNFetchBlobReq;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.modules.core.DeviceEventManagerModule;

import java.io.IOException;
import java.nio.charset.Charset;

import expolib_v1.okhttp3.MediaType;
import expolib_v1.okhttp3.ResponseBody;
import expolib_v1.okio.Buffer;
import expolib_v1.okio.BufferedSource;
import expolib_v1.okio.Okio;
import expolib_v1.okio.Source;
import expolib_v1.okio.Timeout;

/**
 * Created by wkh237 on 2016/7/11.
 */
public class RNFetchBlobDefaultResp extends ResponseBody {

    String mTaskId;
    ReactApplicationContext rctContext;
    ResponseBody originalBody;
    boolean isIncrement = false;

    public RNFetchBlobDefaultResp(ReactApplicationContext ctx, String taskId, ResponseBody body, boolean isIncrement) {
        this.rctContext = ctx;
        this.mTaskId = taskId;
        this.originalBody = body;
        this.isIncrement = isIncrement;
    }

    @Override
    public MediaType contentType() {
        return originalBody.contentType();
    }

    @Override
    public long contentLength() {
        return originalBody.contentLength();
    }

    @Override
    public BufferedSource source() {
        return Okio.buffer(new ProgressReportingSource(originalBody.source()));
    }

    private class ProgressReportingSource implements Source {

        BufferedSource mOriginalSource;
        long bytesRead = 0;

        ProgressReportingSource(BufferedSource originalSource) {
            mOriginalSource = originalSource;
        }

        @Override
        public long read(Buffer sink, long byteCount) throws IOException {

            long read =  mOriginalSource.read(sink, byteCount);
            bytesRead += read > 0 ? read : 0;
            RNFetchBlobProgressConfig reportConfig = RNFetchBlobReq.getReportProgress(mTaskId);
            long cLen = contentLength();
            if(reportConfig != null && cLen != 0 && reportConfig.shouldReport(bytesRead/contentLength())) {
                WritableMap args = Arguments.createMap();
                args.putString("taskId", mTaskId);
                args.putString("written", String.valueOf(bytesRead));
                args.putString("total", String.valueOf(contentLength()));
                if(isIncrement) {
                    args.putString("chunk", sink.readString(Charset.defaultCharset()));
                }
                else {
                    args.putString("chunk", "");
                }

                rctContext.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
                        .emit(RNFetchBlobConst.EVENT_PROGRESS, args);
            }
            return read;
        }

        @Override
        public Timeout timeout() {
            return null;
        }

        @Override
        public void close() throws IOException {

        }
    }

}
