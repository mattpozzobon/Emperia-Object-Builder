/*
*  Copyright (c) 2014-2023 Object Builder <https://github.com/ottools/ObjectBuilder>
*
*  Permission is hereby granted, free of charge, to any person obtaining a copy
*  of this software and associated documentation files (the "Software"), to deal
*  in the Software without restriction, including without limitation the rights
*  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
*  copies of the Software, and to permit persons to whom the Software is
*  furnished to do so, subject to the following conditions:
*
*  The above copyright notice and this permission notice shall be included in
*  all copies or substantial portions of the Software.
*
*  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
*  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
*  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
*  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
*  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
*  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
*  THE SOFTWARE.
*/

package otlib.utils
{
    import flash.events.ErrorEvent;
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.IOErrorEvent;
    import flash.events.ProgressEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.ByteArray;
    import flash.utils.Endian;

    import nail.errors.NullArgumentError;
    import nail.utils.FileUtil;

    import otlib.core.Version;
    import otlib.core.VersionStorage;
    import otlib.core.ClientFeatures;
    import otlib.resources.Resources;

    [Event(name="complete", type="flash.events.Event")]
    [Event(name="progress", type="flash.events.ProgressEvent")]
    [Event(name="error", type="flash.events.ErrorEvent")]

    [ResourceBundle("strings")]

    public class ClientInfoLoader extends EventDispatcher
    {
        // --------------------------------------------------------------------------
        // PROPERTIES
        // --------------------------------------------------------------------------

        private var m_otfi:File;
        private var m_dat:File;
        private var m_spr:File;
        private var m_clientInfo:ClientInfo;
        private var m_total:uint;
        private var m_loaded:uint;
        private var m_datIsEmperia:Boolean;
        private var m_datContentVersion:uint;

        // --------------------------------------
        // Getters / Setters
        // --------------------------------------

        public function get clientInfo():ClientInfo
        {
            return m_clientInfo;
        }

        // --------------------------------------------------------------------------
        // CONSTRUCTOR
        // --------------------------------------------------------------------------

        public function ClientInfoLoader()
        {
        }

        // --------------------------------------------------------------------------
        // METHODS
        // --------------------------------------------------------------------------

        // --------------------------------------
        // Public
        // --------------------------------------

        public function load(dat:File, spr:File, extended:Boolean):void
        {
            if (!dat)
                throw new NullArgumentError("dat");

            if (!spr)
                throw new NullArgumentError("spr");

            if (!dat.exists)
                dispatchEvent(createErrorEvent(Resources.getString("datFileNotFound")));

            if (!spr.exists)
                dispatchEvent(createErrorEvent(Resources.getString("sprFileNotFound")));

            // Search for legacy .otfi manifest (Emperia features come from the binary headers)
            var result:Vector.<File> = FileUtil.findExtension(dat, "otfi");
            if (result.length != 0)
                m_otfi = result[0];

            m_dat = dat;
            m_spr = spr;
            m_clientInfo = new ClientInfo();
            m_clientInfo.features = new ClientFeatures();
            m_clientInfo.features.extended = extended;
            m_total = 3;

            doLoad();
        }

        // --------------------------------------
        // Private
        // --------------------------------------

        private function doLoad():void
        {
            // Step 1: Load OTFI manifest (if present)
            dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, false, false, 1, m_total));
            if (m_otfi)
            {
                var otfi:OTFI = new OTFI();
                if (otfi.load(m_otfi))
                {
                    m_clientInfo.features.extended = otfi.extended;
                    m_clientInfo.features.transparency = otfi.transparency;
                    m_clientInfo.features.improvedAnimations = otfi.improvedAnimations;
                    m_clientInfo.features.frameGroups = otfi.frameGroups;
                    m_clientInfo.features.attributeServer = otfi.attributeServer;
                    m_clientInfo.spriteSize = otfi.spriteSize;
                    m_clientInfo.spriteDataSize = otfi.spriteDataSize;
                }
            }

            // Step 2: Read DAT header
            dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, false, false, 2, m_total));
            var datStream:FileStream = new FileStream();
            datStream.endian = Endian.LITTLE_ENDIAN;
            datStream.open(m_dat, FileMode.READ);
            readMetadaInfo(datStream);
            datStream.close();

            // Step 3: Read SPR header + resolve version
            dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, false, false, 3, m_total));
            var sprFile:File = maybeDecompressGzip(m_spr);
            var sprStream:FileStream = new FileStream();
            sprStream.endian = Endian.LITTLE_ENDIAN;
            sprStream.open(sprFile, FileMode.READ);
            readSpritesInfo(sprStream);
            sprStream.close();

            dispatchEvent(new Event(Event.COMPLETE));
        }

        // --------------------------------------
        // Event Handlers
        // --------------------------------------

        private function readMetadaInfo(stream:FileStream):void
        {
            // Detect Emperia header
            var magic1:uint = stream.readUnsignedInt();
            var magic2:uint = stream.readUnsignedInt();

            if (magic1 == 0x45504D45 && magic2 == 0x00414952)
            {
                // Emperia format: read content version, defer signature resolution
                m_datIsEmperia = true;
                stream.position = 0x0B;
                m_datContentVersion = stream.readUnsignedInt();
                m_clientInfo.datSignature = 0; // placeholder, filled after version lookup
                stream.position = 20; // skip to payload
            }
            else
            {
                // Legacy format: first uint was the signature
                m_datIsEmperia = false;
                stream.position = 4;
                m_clientInfo.datSignature = magic1;
            }

            m_clientInfo.maxItemId = stream.readUnsignedShort();
            m_clientInfo.maxOutfitId = stream.readUnsignedShort();
            m_clientInfo.maxEffectId = stream.readUnsignedShort();
            m_clientInfo.maxMissileId = stream.readUnsignedShort();
        }

        private function readSpritesInfo(stream:FileStream):void
        {
            // Detect Emperia header
            var sprMagic1:uint = stream.readUnsignedInt();
            var sprMagic2:uint = stream.readUnsignedInt();
            var sprIsEmperia:Boolean = (sprMagic1 == 0x45504D45 && sprMagic2 == 0x00414952);

            var sprContentVersion:uint;
            if (sprIsEmperia)
            {
                // Read flags from header (offset 15) to set features
                stream.position = 15;
                var sprFlags:uint = stream.readUnsignedByte();
                m_clientInfo.features.extended = (sprFlags & 0x01) != 0;
                m_clientInfo.features.transparency = (sprFlags & 0x02) != 0;
                m_clientInfo.features.frameGroups = (sprFlags & 0x04) != 0;
                m_clientInfo.features.improvedAnimations = (sprFlags & 0x08) != 0;

                // Emperia assets always use 32px sprites / 4096 data size
                m_clientInfo.spriteSize = 32;
                m_clientInfo.spriteDataSize = 4096;

                stream.position = 0x0B;
                sprContentVersion = stream.readUnsignedInt();
                m_clientInfo.sprSignature = 0; // placeholder
                stream.position = 20; // skip to payload
            }
            else
            {
                stream.position = 4;
                m_clientInfo.sprSignature = sprMagic1;
            }

            var version:Version;
            if (m_datIsEmperia || sprIsEmperia)
            {
                // Emperia format: look up version by content version value
                var contentVer:uint = m_datIsEmperia ? m_datContentVersion : sprContentVersion;
                var versions:Vector.<Version> = VersionStorage.getInstance().getByValue(contentVer);
                if (versions.length > 0)
                    version = versions[0];
            }
            else
            {
                version = VersionStorage.getInstance().getBySignatures(
                        m_clientInfo.datSignature,
                        m_clientInfo.sprSignature);
            }

            if (!version)
            {
                m_clientInfo.maxItemId = 0;
                m_clientInfo.maxOutfitId = 0;
                m_clientInfo.maxEffectId = 0;
                m_clientInfo.maxMissileId = 0;
                m_clientInfo.maxSpriteId = 0;
                return;
            }

            // Backfill real signatures from the resolved version so downstream code works
            if (m_datIsEmperia)
                m_clientInfo.datSignature = version.datSignature;
            if (sprIsEmperia)
                m_clientInfo.sprSignature = version.sprSignature;

            m_clientInfo.clientVersion = version.value;
            m_clientInfo.clientVersionStr = version.valueStr;

            if (m_clientInfo.extended || version.value >= 960)
            {
                m_clientInfo.maxSpriteId = stream.readUnsignedInt();
                m_clientInfo.features.extended = true;
            }
            else
                m_clientInfo.maxSpriteId = stream.readUnsignedShort();
        }


        /**
         * Detects gzip magic bytes (0x1f 0x8b) and decompresses to a temp file if needed.
         * Returns the original file if not gzip-compressed.
         */
        private static function maybeDecompressGzip(file:File):File
        {
            var stream:FileStream = new FileStream();
            stream.open(file, FileMode.READ);
            stream.endian = Endian.LITTLE_ENDIAN;

            if (stream.bytesAvailable < 2)
            {
                stream.close();
                return file;
            }

            var b0:uint = stream.readUnsignedByte();
            var b1:uint = stream.readUnsignedByte();
            stream.close();

            if (b0 != 0x1F || b1 != 0x8B)
                return file;

            // Read entire gzip file
            var raw:ByteArray = new ByteArray();
            stream = new FileStream();
            stream.open(file, FileMode.READ);
            stream.readBytes(raw, 0, stream.bytesAvailable);
            stream.close();

            // Parse gzip header to find DEFLATE stream
            raw.endian = Endian.LITTLE_ENDIAN;
            raw.position = 3;
            var flg:uint = raw.readUnsignedByte();
            raw.position = 10;

            if (flg & 0x04) { var xlen:uint = raw.readUnsignedShort(); raw.position += xlen; }
            if (flg & 0x08) { while (raw.readUnsignedByte() != 0) {} }
            if (flg & 0x10) { while (raw.readUnsignedByte() != 0) {} }
            if (flg & 0x02) { raw.position += 2; }

            var deflateStart:uint = raw.position;
            var deflateLen:uint = raw.length - deflateStart - 8;
            var deflateData:ByteArray = new ByteArray();
            deflateData.writeBytes(raw, deflateStart, deflateLen);
            deflateData.position = 0;
            deflateData.inflate();

            var tmpFile:File = File.createTempFile();
            stream = new FileStream();
            stream.open(tmpFile, FileMode.WRITE);
            stream.writeBytes(deflateData, 0, deflateData.length);
            stream.close();

            return tmpFile;
        }

        private function createErrorEvent(text:String, id:uint = 0):ErrorEvent
        {
            return new ErrorEvent(ErrorEvent.ERROR, false, false, text, id);
        }
    }
}
