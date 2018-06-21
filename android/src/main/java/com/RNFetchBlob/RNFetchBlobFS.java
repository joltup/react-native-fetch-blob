package com.RNFetchBlob;

import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.res.AssetFileDescriptor;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.AsyncTask;
import android.os.Build;
import android.os.Environment;
import android.os.StatFs;
import android.os.SystemClock;
import android.util.Base64;

import com.RNFetchBlob.Utils.PathResolver;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Callback;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.modules.core.DeviceEventManagerModule;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.Charset;
import java.nio.charset.CharsetEncoder;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

public class RNFetchBlobFS {

    ReactApplicationContext mCtx;
    DeviceEventManagerModule.RCTDeviceEventEmitter emitter;
    String encoding = "base64";
    boolean append = false;
    OutputStream writeStreamInstance = null;
    static HashMap<String, RNFetchBlobFS> fileStreams = new HashMap<>();

    RNFetchBlobFS(ReactApplicationContext ctx) {
        this.mCtx = ctx;
        this.emitter = ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class);
    }

    static String getExternalFilePath(ReactApplicationContext ctx, String taskId, RNFetchBlobConfig config) {
        if(config.path != null)
            return config.path;
        else if(config.fileCache && config.appendExt != null)
            return RNFetchBlobFS.getTmpPath(ctx, taskId) + "." + config.appendExt;
        else
            return RNFetchBlobFS.getTmpPath(ctx, taskId);
    }

    /**
     * Write string with encoding to file
     * @param path Destination file path.
     * @param encoding Encoding of the string.
     * @param data Array passed from JS context.
     * @param promise RCT Promise
     */
    static public void writeFile(String path, String encoding, String data, final boolean append, final Promise promise) {
        try {
            int written = 0;
            File f = new File(path);
            File dir = f.getParentFile();
            if(!dir.exists())
                dir.mkdirs();
            FileOutputStream fout = new FileOutputStream(f, append);
            // write data from a file
            if(encoding.equalsIgnoreCase(RNFetchBlobConst.DATA_ENCODE_URI)) {
                data = normalizePath(data);
                File src = new File(data);
                if(!src.exists()) {
                    promise.reject("RNfetchBlob writeFileError", "source file : " + data + "not exists");
                    fout.close();
                    return ;
                }
                FileInputStream fin = new FileInputStream(src);
                byte [] buffer = new byte [10240];
                int read;
                written = 0;
                while((read = fin.read(buffer)) > 0) {
                    fout.write(buffer, 0, read);
                    written += read;
                }
                fin.close();
            }
            else {
                byte[] bytes = stringToBytes(data, encoding);
                fout.write(bytes);
                written = bytes.length;
            }
            fout.close();
            promise.resolve(written);
        } catch (Exception e) {
            promise.reject("RNFetchBlob writeFileError", e.getLocalizedMessage());
        }
    }

    /**
     * Write array of bytes into file
     * @param path Destination file path.
     * @param data Array passed from JS context.
     * @param promise RCT Promise
     */
    static public void writeFile(String path, ReadableArray data, final boolean append, final Promise promise) {

        try {

            File f = new File(path);
            File dir = f.getParentFile();
            if(!dir.exists())
                dir.mkdirs();
            FileOutputStream os = new FileOutputStream(f, append);
            byte [] bytes = new byte[data.size()];
            for(int i=0;i<data.size();i++) {
                bytes[i] = (byte) data.getInt(i);
            }
            os.write(bytes);
            os.close();
            promise.resolve(data.size());
        } catch (Exception e) {
            promise.reject("RNFetchBlob writeFileError", e.getLocalizedMessage());
        }
    }

    /**
     * Read file with a buffer that has the same size as the target file.
     * @param path  Path of the file.
     * @param encoding  Encoding of read stream.
     * @param promise
     */
    static public void readFile(String path, String encoding, final Promise promise ) {
        String resolved = normalizePath(path);
        if(resolved != null)
            path = resolved;
        try {
            byte[] bytes;

            if(resolved != null && resolved.startsWith(RNFetchBlobConst.FILE_PREFIX_BUNDLE_ASSET)) {
                String assetName = path.replace(RNFetchBlobConst.FILE_PREFIX_BUNDLE_ASSET, "");
                long length = RNFetchBlob.RCTContext.getAssets().openFd(assetName).getLength();
                bytes = new byte[(int) length];
                InputStream in = RNFetchBlob.RCTContext.getAssets().open(assetName);
                in.read(bytes, 0, (int) length);
                in.close();
            }
            // issue 287
            else if(resolved == null) {
                InputStream in = RNFetchBlob.RCTContext.getContentResolver().openInputStream(Uri.parse(path));
                int length = (int) in.available();
                bytes = new byte[length];
                in.read(bytes);
                in.close();
            }
            else {
                File f = new File(path);
                int length = (int) f.length();
                bytes = new byte[length];
                FileInputStream in = new FileInputStream(f);
                in.read(bytes);
                in.close();
            }

            switch (encoding.toLowerCase()) {
                case "base64" :
                    promise.resolve(Base64.encodeToString(bytes, Base64.NO_WRAP));
                    break;
                case "ascii" :
                    WritableArray asciiResult = Arguments.createArray();
                    for(byte b : bytes) {
                        asciiResult.pushInt((int)b);
                    }
                    promise.resolve(asciiResult);
                    break;
                case "utf8" :
                    promise.resolve(new String(bytes));
                    break;
                default:
                    promise.resolve(new String(bytes));
                    break;
            }
        }
        catch(Exception err) {
            promise.reject("ReadFile Error", err.getLocalizedMessage());
        }

    }

    /**
     * Static method that returns system folders to JS context
     * @param ctx   React Native application context
     */
    static public Map<String, Object> getSystemfolders(ReactApplicationContext ctx) {
        Map<String, Object> res = new HashMap<>();

        res.put("DocumentDir", ctx.getFilesDir().getAbsolutePath());
        res.put("CacheDir", ctx.getCacheDir().getAbsolutePath());
        res.put("DCIMDir", Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM).getAbsolutePath());
        res.put("PictureDir", Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES).getAbsolutePath());
        res.put("MusicDir", Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC).getAbsolutePath());
        res.put("DownloadDir", Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).getAbsolutePath());
        res.put("MovieDir", Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES).getAbsolutePath());
        res.put("RingtoneDir", Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_RINGTONES).getAbsolutePath());
        String state;
        state = Environment.getExternalStorageState();
        if (state.equals(Environment.MEDIA_MOUNTED)) {
            res.put("SDCardDir", Environment.getExternalStorageDirectory().getAbsolutePath());

            File externalDirectory = ctx.getExternalFilesDir(null);
            if (externalDirectory != null) {
                res.put("SDCardApplicationDir", externalDirectory.getParentFile().getAbsolutePath());
            }
        }
        res.put("MainBundleDir", ctx.getApplicationInfo().dataDir);
        return res;
    }

    /**
     * Static method that returns a temp file path
     * @param ctx   React Native application context
     * @param taskId    An unique string for identify
     * @return
     */
    static public String getTmpPath(ReactApplicationContext ctx, String taskId) {
        return RNFetchBlob.RCTContext.getFilesDir() + "/RNFetchBlobTmp_" + taskId;
    }

    /**
     * Create a file stream for read
     * @param path  File stream target path
     * @param encoding  File stream decoder, should be one of `base64`, `utf8`, `ascii`
     * @param bufferSize    Buffer size of read stream, default to 4096 (4095 when encode is `base64`)
     */
    public void readStream(String path, String encoding, int bufferSize, int tick, final String streamId) {
        String resolved = normalizePath(path);
        if(resolved != null)
            path = resolved;
        try {

            int chunkSize = encoding.equalsIgnoreCase("base64") ? 4095 : 4096;
            if(bufferSize > 0)
                chunkSize = bufferSize;

            InputStream fs;

            if(resolved != null && path.startsWith(RNFetchBlobConst.FILE_PREFIX_BUNDLE_ASSET)) {
                fs = RNFetchBlob.RCTContext.getAssets().open(path.replace(RNFetchBlobConst.FILE_PREFIX_BUNDLE_ASSET, ""));

            }
            // fix issue 287
            else if(resolved == null) {
                fs = RNFetchBlob.RCTContext.getContentResolver().openInputStream(Uri.parse(path));
            }
            else {
                fs = new FileInputStream(new File(path));
            }

            byte[] buffer = new byte[chunkSize];
            int cursor = 0;
            boolean error = false;

            if (encoding.equalsIgnoreCase("utf8")) {
                CharsetEncoder encoder = Charset.forName("UTF-8").newEncoder();
                while ((cursor = fs.read(buffer)) != -1) {
                    encoder.encode(ByteBuffer.wrap(buffer).asCharBuffer());
                    String chunk = new String(buffer, 0, cursor);
                    emitStreamEvent(streamId, "data", chunk);
                    if(tick > 0)
                        SystemClock.sleep(tick);
                }
            } else if (encoding.equalsIgnoreCase("ascii")) {
                while ((cursor = fs.read(buffer)) != -1) {
                    WritableArray chunk = Arguments.createArray();
                    for(int i =0;i<cursor;i++)
                    {
                        chunk.pushInt((int)buffer[i]);
                    }
                    emitStreamEvent(streamId, "data", chunk);
                    if(tick > 0)
                        SystemClock.sleep(tick);
                }
            } else if (encoding.equalsIgnoreCase("base64")) {
                while ((cursor = fs.read(buffer)) != -1) {
                    if(cursor < chunkSize) {
                        byte [] copy = new byte[cursor];
                        for(int i =0;i<cursor;i++) {
                            copy[i] = buffer[i];
                        }
                        emitStreamEvent(streamId, "data", Base64.encodeToString(copy, Base64.NO_WRAP));
                    }
                    else
                        emitStreamEvent(streamId, "data", Base64.encodeToString(buffer, Base64.NO_WRAP));
                    if(tick > 0)
                        SystemClock.sleep(tick);
                }
            } else {
                String msg = "unrecognized encoding `" + encoding + "`";
                emitStreamEvent(streamId, "error", msg);
                error = true;
            }

            if(!error)
                emitStreamEvent(streamId, "end", "");
            fs.close();
            buffer = null;

        } catch (Exception err) {
            emitStreamEvent(streamId, "warn", "Failed to convert data to "+encoding+" encoded string, this might due to the source data is not able to convert using this encoding.");
            err.printStackTrace();
        }
    }

    /**
     * Create a write stream and store its instance in RNFetchBlobFS.fileStreams
     * @param path  Target file path
     * @param encoding Should be one of `base64`, `utf8`, `ascii`
     * @param append    Flag represents if the file stream overwrite existing content
     * @param callback
     */
    public void writeStream(String path, String encoding, boolean append, Callback callback) {
        File dest = new File(path);
        if(!dest.exists() || dest.isDirectory()) {
            callback.invoke("write stream error: target path `" + path + "` may not exists or it's a folder");
            return;
        }
        try {
            OutputStream fs = new FileOutputStream(path, append);
            this.encoding = encoding;
            this.append = append;
            String streamId = UUID.randomUUID().toString();
            RNFetchBlobFS.fileStreams.put(streamId, this);
            this.writeStreamInstance = fs;
            callback.invoke(null, streamId);
        } catch(Exception err) {
            callback.invoke("write stream error: failed to create write stream at path `"+path+"` "+ err.getLocalizedMessage());
        }

    }

    /**
     * Write a chunk of data into a file stream.
     * @param streamId File stream ID
     * @param data  Data chunk in string format
     * @param callback JS context callback
     */
    static void writeChunk(String streamId, String data, Callback callback) {

        RNFetchBlobFS fs = fileStreams.get(streamId);
        OutputStream stream = fs.writeStreamInstance;
        byte [] chunk = RNFetchBlobFS.stringToBytes(data, fs.encoding);

        try {
            stream.write(chunk);
            callback.invoke();
        } catch (Exception e) {
            callback.invoke(e.getLocalizedMessage());
        }
    }

    /**
     * Write data using ascii array
     * @param streamId File stream ID
     * @param data  Data chunk in ascii array format
     * @param callback JS context callback
     */
    static void writeArrayChunk(String streamId, ReadableArray data, Callback callback) {

        try {
            RNFetchBlobFS fs = fileStreams.get(streamId);
            OutputStream stream = fs.writeStreamInstance;
            byte [] chunk = new byte[data.size()];
            for(int i =0; i< data.size();i++) {
                chunk[i] = (byte) data.getInt(i);
            }
            stream.write(chunk);
            callback.invoke();
        } catch (Exception e) {
            callback.invoke(e.getLocalizedMessage());
        }
    }

    /**
     * Close file write stream by ID
     * @param streamId Stream ID
     * @param callback JS context callback
     */
    static void closeStream(String streamId, Callback callback) {
        try {
            RNFetchBlobFS fs = fileStreams.get(streamId);
            OutputStream stream = fs.writeStreamInstance;
            fileStreams.remove(streamId);
            stream.close();
            callback.invoke();
        } catch(Exception err) {
            callback.invoke(err.getLocalizedMessage());
        }
    }

    /**
     * Unlink file at path
     * @param path  Path of target
     * @param callback  JS context callback
     */
    static void unlink(String path, Callback callback) {
        try {
            RNFetchBlobFS.deleteRecursive(new File(path));
            callback.invoke(null, true);
        } catch(Exception err) {
            if(err != null)
            callback.invoke(err.getLocalizedMessage(), false);
        }
    }

    static void deleteRecursive(File fileOrDirectory) {

        if (fileOrDirectory.isDirectory()) {
            for (File child : fileOrDirectory.listFiles()) {
                deleteRecursive(child);
            }
        }
        fileOrDirectory.delete();
    }

    /**
     * Make a folder
     * @param path Source path
     * @param callback  JS context callback
     */
    static void mkdir(String path, Callback callback) {
        File dest = new File(path);
        if(dest.exists()) {
            callback.invoke("mkdir error: failed to create folder at `" + path + "` folder already exists");
            return;
        }
        dest.mkdirs();
        callback.invoke();
    }
    /**
     * Copy file to destination path
     * @param path Source path
     * @param dest Target path
     * @param callback  JS context callback
     */
    static void cp(String path, String dest, Callback callback) {

        path = normalizePath(path);
        InputStream in = null;
        OutputStream out = null;

        try {

            if(!isPathExists(path)) {
                callback.invoke("cp error: source file at path`" + path + "` not exists");
                return;
            }
            if(!new File(dest).exists())
                new File(dest).createNewFile();

            in = inputStreamFromPath(path);
            out = new FileOutputStream(dest);

            byte[] buf = new byte[10240];
            int len;
            while ((len = in.read(buf)) > 0) {
                out.write(buf, 0, len);
            }

        } catch (Exception err) {
            callback.invoke(err.getLocalizedMessage());
        } finally {
            try {
                if (in != null) {
                    in.close();
                }
                if (out != null) {
                    out.close();
                }
                callback.invoke();
            } catch (Exception e) {
                callback.invoke(e.getLocalizedMessage());
            }
        }
    }

    /**
     * Move file
     * @param path Source file path
     * @param dest Destination file path
     * @param callback JS context callback
     */
    static void mv(String path, String dest, Callback callback) {
        File src = new File(path);
        if(!src.exists()) {
            callback.invoke("mv error: source file at path `" + path + "` does not exists");
            return;
        }
        src.renameTo(new File(dest));
        callback.invoke();
    }

    /**
     * Check if the path exists, also check if it is a folder when exists.
     * @param path Path to check
     * @param callback  JS context callback
     */
    static void exists(String path, Callback callback) {

        if(isAsset(path)) {
            try {
                String filename = path.replace(RNFetchBlobConst.FILE_PREFIX_BUNDLE_ASSET, "");
                AssetFileDescriptor fd = RNFetchBlob.RCTContext.getAssets().openFd(filename);
                callback.invoke(true, false);
            } catch (IOException e) {
                callback.invoke(false, false);
            }
        }
        else {
            path = normalizePath(path);
            boolean exist = new File(path).exists();
            boolean isDir = new File(path).isDirectory();
            callback.invoke(exist, isDir);
        }
    }

    /**
     * List content of folder
     * @param path Target folder
     * @param callback  JS context callback
     */
    static void ls(String path, Callback callback) {
        path = normalizePath(path);
        File src = new File(path);
        if (!src.exists() || !src.isDirectory()) {
            callback.invoke("ls error: failed to list path `" + path + "` for it is not exist or it is not a folder");
            return;
        }
        String[] files = new File(path).list();
        WritableArray arg = Arguments.createArray();
        if(files!=null) {
            for (String i : files) {
                arg.pushString(i);
            }
        }
        callback.invoke(null, arg);
    }

    /**
     * Create a file by slicing given file path
     * @param src   Source file path
     * @param dest  Destination of created file
     * @param start Start byte offset in source file
     * @param end   End byte offset
     * @param encode NOT IMPLEMENTED
     */
    public static void slice(String src, String dest, int start, int end, String encode, Promise promise) {
        try {
            src = normalizePath(src);
            File source = new File(src);
            if(!source.exists()) {
                promise.reject("RNFetchBlob.slice error", "source file : " + src + " not exists");
                return;
            }
            long size = source.length();
            long max = Math.min(size, end);
            long expected = max - start;
            long now = 0;
            FileInputStream in = new FileInputStream(new File(src));
            FileOutputStream out = new FileOutputStream(new File(dest));
            in.skip(start);
            byte [] buffer = new byte[10240];
            while(now < expected) {
                long read = in.read(buffer, 0, 10240);
                long remain = expected - now;
                if(read <= 0) {
                    break;
                }
                out.write(buffer, 0, (int) Math.min(remain, read));
                now += read;
            }
            in.close();
            out.flush();
            out.close();
            promise.resolve(dest);
        } catch (Exception e) {
            e.printStackTrace();
            promise.reject(e.getLocalizedMessage());
        }
    }

    static void lstat(String path, final Callback callback) {
        path = normalizePath(path);

        new AsyncTask<String, Integer, Integer>() {
            @Override
            protected Integer doInBackground(String ...args) {
                WritableArray res = Arguments.createArray();
                if(args[0] == null) {
                    callback.invoke("lstat error: the path specified for lstat is either `null` or `undefined`.");
                    return 0;
                }
                File src = new File(args[0]);
                if(!src.exists()) {
                    callback.invoke("lstat error: failed to list path `" + args[0] + "` for it is not exist or it is not a folder");
                    return 0;
                }
                if(src.isDirectory()) {
                    String [] files = src.list();
                    for(String p : files) {
                        res.pushMap(statFile ( src.getPath() + "/" + p));
                    }
                }
                else {
                    res.pushMap(statFile(src.getAbsolutePath()));
                }
                callback.invoke(null, res);
                return 0;
            }
        }.execute(path);
    }

    /**
     * show status of a file or directory
     * @param path
     * @param callback
     */
    static void stat(String path, Callback callback) {
        try {
            path = normalizePath(path);
            WritableMap result = statFile(path);
            if(result == null)
                callback.invoke("stat error: failed to list path `" + path + "` for it is not exist or it is not a folder", null);
            else
                callback.invoke(null, result);
        } catch(Exception err) {
            callback.invoke(err.getLocalizedMessage());
        }
    }

    /**
     * Basic stat method
     * @param path
     * @return Stat result of a file or path
     */
    static WritableMap statFile(String path) {
        try {
            path = normalizePath(path);
            WritableMap stat = Arguments.createMap();
            if(isAsset(path)) {
                String name = path.replace(RNFetchBlobConst.FILE_PREFIX_BUNDLE_ASSET, "");
                AssetFileDescriptor fd = RNFetchBlob.RCTContext.getAssets().openFd(name);
                stat.putString("filename", name);
                stat.putString("path", path);
                stat.putString("type", "asset");
                stat.putString("size", String.valueOf(fd.getLength()));
                stat.putInt("lastModified", 0);
            }
            else {
                File target = new File(path);
                if (!target.exists()) {
                    return null;
                }
                stat.putString("filename", target.getName());
                stat.putString("path", target.getPath());
                stat.putString("type", target.isDirectory() ? "directory" : "file");
                stat.putString("size", String.valueOf(target.length()));
                String lastModified = String.valueOf(target.lastModified());
                stat.putString("lastModified", lastModified);

            }
            return stat;
        } catch(Exception err) {
            return null;
        }
    }

    /**
     * Media scanner scan file
     * @param path
     * @param mimes
     * @param callback
     */
    void scanFile(String [] path, String[] mimes, final Callback callback) {
        try {
            MediaScannerConnection.scanFile(mCtx, path, mimes, new MediaScannerConnection.OnScanCompletedListener() {
                @Override
                public void onScanCompleted(String s, Uri uri) {
                    callback.invoke(null, true);
                }
            });
        } catch(Exception err) {
            callback.invoke(err.getLocalizedMessage(), null);
        }
    }

    /**
     * Create new file at path
     * @param path The destination path of the new file.
     * @param data Initial data of the new file.
     * @param encoding Encoding of initial data.
     * @param callback RCT bridge callback.
     */
    static void createFile(String path, String data, String encoding, Callback callback) {
        try {
            File dest = new File(path);
            boolean created = dest.createNewFile();
            if(encoding.equals(RNFetchBlobConst.DATA_ENCODE_URI)) {
                String orgPath = data.replace(RNFetchBlobConst.FILE_PREFIX, "");
                File src = new File(orgPath);
                if(!src.exists()) {
                    callback.invoke("RNfetchBlob writeFileError", "source file : " + data + "not exists");
                    return ;
                }
                FileInputStream fin = new FileInputStream(src);
                OutputStream ostream = new FileOutputStream(dest);
                byte [] buffer = new byte [10240];
                int read = fin.read(buffer);
                while(read > 0) {
                    ostream.write(buffer, 0, read);
                    read = fin.read(buffer);
                }
                fin.close();
                ostream.close();
            }
            else {
                if (!created) {
                    callback.invoke("create file error: failed to create file at path `" + path + "` for its parent path may not exists, or the file already exists. If you intended to overwrite the existing file use fs.writeFile instead.");
                    return;
                }
                OutputStream ostream = new FileOutputStream(dest);
                ostream.write(RNFetchBlobFS.stringToBytes(data, encoding));
            }
            callback.invoke(null, path);
        } catch(Exception err) {
            callback.invoke(err.getLocalizedMessage());
        }
    }

    /**
     * Create file for ASCII encoding
     * @param path  Path of new file.
     * @param data  Content of new file
     * @param callback  JS context callback
     */
    static void createFileASCII(String path, ReadableArray data, Callback callback) {
        try {
            File dest = new File(path);
            if(dest.exists()) {
                callback.invoke("create file error: failed to create file at path `" + path + "`, file already exists.");
                return;
            }
            boolean created = dest.createNewFile();
            if(!created) {
                callback.invoke("create file error: failed to create file at path `" + path + "` for its parent path may not exists");
                return;
            }
            OutputStream ostream = new FileOutputStream(dest);
            byte [] chunk = new byte[data.size()];
            for(int i =0; i<data.size();i++) {
                chunk[i] = (byte) data.getInt(i);
            }
            ostream.write(chunk);
            chunk = null;
            callback.invoke(null, path);
        } catch(Exception err) {
            callback.invoke(err.getLocalizedMessage());
        }
    }

    static void df(Callback callback) {
        StatFs stat = new StatFs(Environment.getDataDirectory().getPath());
        WritableMap args = Arguments.createMap();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            args.putString("internal_free", String.valueOf(stat.getFreeBytes()));
            args.putString("internal_total", String.valueOf(stat.getTotalBytes()));
            StatFs statEx = new StatFs(Environment.getExternalStorageDirectory().getPath());
            args.putString("external_free", String.valueOf(statEx.getFreeBytes()));
            args.putString("external_total", String.valueOf(statEx.getTotalBytes()));

        }
        callback.invoke(null ,args);
    }

    /**
     * Remove files in session.
     * @param paths An array of file paths.
     * @param callback JS contest callback
     */
    static void removeSession(ReadableArray paths, final Callback callback) {

        AsyncTask<ReadableArray, Integer, Integer> task = new AsyncTask<ReadableArray, Integer, Integer>() {
            @Override
            protected Integer doInBackground(ReadableArray ...paths) {
                try {
                    for (int i = 0; i < paths[0].size(); i++) {
                        File f = new File(paths[0].getString(i));
                        if (f.exists())
                            f.delete();
                    }
                    callback.invoke(null, true);
                } catch(Exception err) {
                    callback.invoke(err.getLocalizedMessage());
                }
                return paths[0].size();
            }
        };
        task.execute(paths);
    }

    /**
     * String to byte converter method
     * @param data  Raw data in string format
     * @param encoding Decoder name
     * @return  Converted data byte array
     */
    private static byte[] stringToBytes(String data, String encoding) {
        if(encoding.equalsIgnoreCase("ascii")) {
            return data.getBytes(Charset.forName("US-ASCII"));
        }
        else if(encoding.toLowerCase().contains("base64")) {
            return Base64.decode(data, Base64.NO_WRAP);

        }
        else if(encoding.equalsIgnoreCase("utf8")) {
            return data.getBytes(Charset.forName("UTF-8"));
        }
        return data.getBytes(Charset.forName("US-ASCII"));
    }

    /**
     * Private method for emit read stream event.
     * @param streamName    ID of the read stream
     * @param event Event name, `data`, `end`, `error`, etc.
     * @param data  Event data
     */
    private void emitStreamEvent(String streamName, String event, String data) {
        WritableMap eventData = Arguments.createMap();
        eventData.putString("event", event);
        eventData.putString("detail", data);
        this.emitter.emit(streamName, eventData);
    }

    private void emitStreamEvent(String streamName, String event, WritableArray data) {
        WritableMap eventData = Arguments.createMap();
        eventData.putString("event", event);
        eventData.putArray("detail", data);
        this.emitter.emit(streamName, eventData);
    }

    // TODO : should we remove this ?
    void emitFSData(String taskId, String event, String data) {
        WritableMap eventData = Arguments.createMap();
        eventData.putString("event", event);
        eventData.putString("detail", data);
        this.emitter.emit("RNFetchBlobStream" + taskId, eventData);
    }

    /**
     * Get input stream of the given path, when the path is a string starts with bundle-assets://
     * the stream is created by Assets Manager, otherwise use FileInputStream.
     * @param path The file to open stream
     * @return InputStream instance
     * @throws IOException
     */
    static InputStream inputStreamFromPath(String path) throws IOException {
        if (path.startsWith(RNFetchBlobConst.FILE_PREFIX_BUNDLE_ASSET)) {
            return RNFetchBlob.RCTContext.getAssets().open(path.replace(RNFetchBlobConst.FILE_PREFIX_BUNDLE_ASSET, ""));
        }
        return new FileInputStream(new File(path));
    }

    /**
     * Check if the asset or the file exists
     * @param path A file path URI string
     * @return A boolean value represents if the path exists.
     */
    static boolean isPathExists(String path) {
        if(path.startsWith(RNFetchBlobConst.FILE_PREFIX_BUNDLE_ASSET)) {
            try {
                RNFetchBlob.RCTContext.getAssets().open(path.replace(RNFetchBlobConst.FILE_PREFIX_BUNDLE_ASSET, ""));
            } catch (IOException e) {
                return false;
            }
            return true;
        }
        else {
            return new File(path).exists();
        }

    }

    static boolean isAsset(String path) {
        if(path != null)
            return path.startsWith(RNFetchBlobConst.FILE_PREFIX_BUNDLE_ASSET);
        return false;
    }

    /**
     * Normalize the path, remove URI scheme (xxx://) so that we can handle it.
     * @param path URI string.
     * @return Normalized string
     */
    static String normalizePath(String path) {
        if(path == null)
            return null;
        if(!path.matches("\\w+\\:.*"))
            return path;
        if(path.startsWith("file://")) {
            return path.replace("file://", "");
        }

        Uri uri = Uri.parse(path);
        if(path.startsWith(RNFetchBlobConst.FILE_PREFIX_BUNDLE_ASSET)) {
            return path;
        }
        else
            return PathResolver.getRealPathFromURI(RNFetchBlob.RCTContext, uri);
    }

}
