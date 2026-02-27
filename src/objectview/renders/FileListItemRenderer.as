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

package objectview.renders
{
    import flash.display.BitmapData;
    import flash.filesystem.File;
    import flash.utils.Dictionary;
    import flash.events.MouseEvent;

    import mx.core.FlexGlobals;
    import mx.graphics.SolidColor;

    import spark.components.Label;
    import spark.components.supportClasses.ItemRenderer;
    import spark.primitives.BitmapImage;
    import spark.primitives.Rect;

    import com.mignari.utils.FileUtil;

    import ob.core.IObjectBuilder;
    import ob.settings.ObjectBuilderSettings;

    import otlib.animation.FrameGroup;
    import otlib.things.FrameGroupType;
    import otlib.things.ThingCategory;
    import otlib.things.ThingData;

    public class FileListItemRenderer extends ItemRenderer
    {
        private static const CACHE:Dictionary = new Dictionary();

        private var _imageDisplay:BitmapImage;
        private var _nameLabel:Label;
        private var _bgRect:Rect; // For Image Background
        private var _fill:Rect; // For Renderer Background

        private var _hovered:Boolean = false;

        private static const COLOR_NORMAL:uint = 0x111111;
        private static const COLOR_HOVERED:uint = 0x3385B2;
        private static const COLOR_SELECTED:uint = 0x156692;

        private static const COLOR_IMAGE_BG:uint = 0x111111; // Wait, old code had 0x535353 for image bg.
        // Let's rename _bgRect to _imageBgRect to avoid confusion.

        public function FileListItemRenderer()
        {
            super();
            this.minHeight = 36;
            this.maxHeight = 132;
            this.minHeight = 36;
            this.maxHeight = 132;
            this.autoDrawBackground = false;
        }

        override protected function createChildren():void
        {
            super.createChildren();

            // 1. Renderer Background Fill
            _fill = new Rect();
            _fill.left = 0;
            _fill.right = 0;
            _fill.top = 0;
            _fill.bottom = 0;
            _fill.fill = new SolidColor(COLOR_NORMAL, 0); // Start transparent? Or Opaque?
            // If I set 0x535353 it will be dark gray.
            // If List has alternating colors, this ruins it. But ThingListRenderer doesn't support alternating colors (it forces one color).
            // So we force one color.
            SolidColor(_fill.fill).color = COLOR_NORMAL;
            SolidColor(_fill.fill).alpha = 1; // Make it opaque
            addElement(_fill);

            // 2. Image Background (existing _bgRect logic)
            _bgRect = new Rect();
            _bgRect.left = 3;
            _bgRect.verticalCenter = 0;
            _bgRect.fill = new SolidColor(COLOR_IMAGE_BG);
            addElement(_bgRect);

            this.addEventListener(MouseEvent.ROLL_OVER, rollOverHandler);
            this.addEventListener(MouseEvent.ROLL_OUT, rollOutHandler);

            _imageDisplay = new BitmapImage();
            _imageDisplay.left = 3;
            _imageDisplay.verticalCenter = 0;
            // Min 32x32, Max 128x128 handled in set data or updateDisplayList?
            // The Original MXML had minWidth/Height and maxWidth/Height on BitmapImage.
            addElement(_imageDisplay);

            _nameLabel = new Label();
            _nameLabel.id = "nameLabel"; // Keep ID for consistency if referenced
            addElement(_nameLabel);
        }

        protected function rollOverHandler(event:MouseEvent):void
        {
            _hovered = true;
            invalidateDisplayList();
        }

        protected function rollOutHandler(event:MouseEvent):void
        {
            _hovered = false;
            invalidateDisplayList();
        }

        override public function set selected(value:Boolean):void
        {
            super.selected = value;
            invalidateDisplayList();
        }

        override protected function updateDisplayList(unscaledWidth:Number, unscaledHeight:Number):void
        {
            super.updateDisplayList(unscaledWidth, unscaledHeight);

            // Background Color
            var color:uint = COLOR_NORMAL;
            if (selected)
                color = COLOR_SELECTED;
            else if (_hovered)
                color = COLOR_HOVERED;

            if (_fill && _fill.fill is SolidColor)
            {
                SolidColor(_fill.fill).color = color;
            }

            // Layout
            var imgW:Number = _imageDisplay.getPreferredBoundsWidth();
            var imgH:Number = _imageDisplay.getPreferredBoundsHeight();

            // Constrain Image size
            if (imgW < 32)
                imgW = 32;
            if (imgH < 32)
                imgH = 32;
            if (imgW > 128)
                imgW = 128;
            if (imgH > 128)
                imgH = 128;

            _imageDisplay.setLayoutBoundsSize(imgW, imgH);
            _imageDisplay.setLayoutBoundsPosition(3, (unscaledHeight - imgH) / 2); // vertically centered

            // Update BG Rect to match Image
            _bgRect.width = imgW;
            _bgRect.height = imgH;

            // Label
            // Left of label = 3 + imgW + 8 (gap)
            var labelX:Number = 3 + imgW + 8;
            var labelW:Number = unscaledWidth - labelX - 2; // padding

            _nameLabel.setLayoutBoundsPosition(labelX, (unscaledHeight - _nameLabel.getPreferredBoundsHeight()) / 2);
            _nameLabel.setLayoutBoundsSize(labelW, NaN);
        }

        override public function set data(value:Object):void
        {
            super.data = value;
            var file:File = value as File;

            if (!file || !file.exists)
            {
                _imageDisplay.source = null;
                _nameLabel.text = "";
                return;
            }

            _nameLabel.text = FileUtil.getName(file);

            var path:String = file.nativePath;
            var cachedData:ThingData = CACHE[path];

            if (cachedData)
            {
                updateImage(cachedData);
            }
            else
            {
                // Load it
                try
                {
                    var settings:ObjectBuilderSettings = IObjectBuilder(FlexGlobals.topLevelApplication).settings;
                    var loadedData:ThingData = ThingData.createFromFile(file, settings);
                    if (loadedData)
                    {
                        CACHE[path] = loadedData;
                        updateImage(loadedData);
                    }
                }
                catch (error:Error)
                {
                    _imageDisplay.source = null;
                }
            }
        }

        private function updateImage(thingData:ThingData):void
        {
            var patternX:uint = 0;
            if (thingData.category == ThingCategory.OUTFIT)
                patternX = 2;

            var frameGroup:FrameGroup = thingData.getFrameGroup(FrameGroupType.DEFAULT);
            var bitmap:BitmapData = thingData.getBitmap(frameGroup, 0, patternX);
            _imageDisplay.source = bitmap;

            invalidateDisplayList(); // Re-layout because image size might change
        }
    }
}
