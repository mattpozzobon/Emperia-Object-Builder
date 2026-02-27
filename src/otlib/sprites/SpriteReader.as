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

package otlib.sprites
{
    import flash.filesystem.FileStream;
    import flash.utils.Endian;
    import otlib.core.ClientFeatures;

    public class SpriteReader extends FileStream implements ISpriteReader
    {
        // --------------------------------------------------------------------------
        // PROPERTIES
        // --------------------------------------------------------------------------

        private var m_extended:Boolean;
        private var m_transparency:Boolean;
        private var m_headerSize:uint;
        private var m_payloadOffset:uint; // 0 for legacy, 16 for Emperia (20 - 4 legacy sig)

        // --------------------------------------------------------------------------
        // CONSTRUCTOR
        // --------------------------------------------------------------------------

        public function SpriteReader(features:ClientFeatures)
        {
            m_extended = features ? features.extended : false;
            m_transparency = features ? features.transparency : false;
            m_headerSize = m_extended ? SpriteFileSize.HEADER_U32 : SpriteFileSize.HEADER_U16;
            m_payloadOffset = 0;

            endian = Endian.LITTLE_ENDIAN;
        }

        // --------------------------------------------------------------------------
        // METHODS
        // --------------------------------------------------------------------------

        // --------------------------------------
        // Public
        // --------------------------------------

        public function readSignature():uint
        {
            // Detect Emperia header: "EMPERIA\0" = 0x45 0x4D 0x50 0x45 0x52 0x49 0x41 0x00
            position = 0;
            var magic1:uint = readUnsignedInt();
            var magic2:uint = readUnsignedInt();

            if (magic1 == 0x45504D45 && magic2 == 0x00414952)
            {
                // Emperia format: header is 20 bytes, payload starts at offset 20
                m_payloadOffset = 16; // 20 - 4 (legacy sig size)

                // Read flags from header (offset 15, 1 byte) to override features
                position = 15;
                var flags:uint = readUnsignedByte();
                m_extended = (flags & 0x01) != 0;
                m_transparency = (flags & 0x02) != 0;

                // Read content version from header (offset 0x0B, 4 bytes LE)
                position = 0x0B;
                var contentVersion:uint = readUnsignedInt();

                // Recalculate header size with offset
                m_headerSize = m_payloadOffset + (m_extended ? SpriteFileSize.HEADER_U32 : SpriteFileSize.HEADER_U16);
                return contentVersion;
            }
            else
            {
                // Legacy format: first 4 bytes are the signature
                m_payloadOffset = 0;
                position = SpriteFilePosition.SIGNATURE;
                return magic1;
            }
        }

        public function readSpriteCount():uint
        {
            position = m_payloadOffset + SpriteFilePosition.LENGTH;
            return m_extended ? readUnsignedInt() : readUnsignedShort();
        }

        public function readSprite(id:uint):Sprite
        {
            position = ((id - 1) * SpriteFileSize.ADDRESS) + m_headerSize;

            var address:uint = readUnsignedInt();
            if (address == 0)
                return null;

            position = address;
            readUnsignedByte(); // skip red color
            readUnsignedByte(); // skip green color
            readUnsignedByte(); // skip blue color

            var sprite:Sprite = new Sprite(id, m_transparency);
            var length:uint = readUnsignedShort();

            if (length != 0)
            {
                readBytes(sprite.compressedPixels, 0, length);
            }

            return sprite;
        }

        public function isEmptySprite(id:uint):Boolean
        {
            position = ((id - 1) * SpriteFileSize.ADDRESS) + m_headerSize;

            var address:uint = readUnsignedInt();
            if (address == 0)
                return true;

            position = address;
            readUnsignedByte(); // skip red color
            readUnsignedByte(); // skip green color
            readUnsignedByte(); // skip blue color

            return readUnsignedShort() == 0;
        }
    }
}
