﻿Class eAutocomplete {

	/*
		Enables users to quickly find and select from a dynamic pre-populated list of suggestions as they type in an AHK Edit control, leveraging searching and filtering.
		https://github.com/A-AhkUser/eAutocomplete
	*/

	; ============================ public properties /============================

	static sources := {"Default": {list: "", path: ""}}

	source := "" ; the current word completion's source
	HWND := ""
	AHKID := ""
	menu := {HWND: "", AHKID: "", _selectedItem: 0}
	onEvent {
		set {
			if (IsFunc(_fn:=value)) {
				((_fn.minParams = "") && _fn:=Func(_fn)) ; handles function references as well as function names
				this._onEvent := _fn
			} else this._onEvent := ""
		return _fn
		}
		get {
		return this._onEvent
		}
	}
	menuOnEvent {
		set {
			if (IsFunc(_fn:=value)) {
				((_fn.minParams = "") && _fn:=Func(_fn)) ; handles function references as well as function names
				this._menuOnEvent := _fn
				GuiControl +g, % this.menu.HWND, % _fn ; set the function object which handles the listbox control's events
			} else {
				_hwnd := this.menu.HWND
				GuiControl -g, % _hwnd ; removes the function object bound to the control
				GuiControl,, % _hwnd, % this.delimiter
			}
		return _fn
		}
		get {
		return this._menuOnEvent
		}
	}
	minSize := {w: 21, h: 21}
	maxSize := {w: A_ScreenWidth, h: A_ScreenHeight}
	onSize {
		set {
			if (IsFunc(_fn:=value)) {
				((_fn.minParams = "") && _fn:=Func(_fn)) ; handles function references as well as function names
				this._onSize := _fn
			} else this._onSize := ""
		return _fn
		}
		get {
		return this._onSize
		}
	}
	disabled {
		set {
			if (this._enabled:=!value) {
				_fn := this._suggestWordList.bind(this)
				GuiControl +g, % this.HWND, % _fn ; set the function object which handles the edit control's events
				this.menuOnEvent := this._menuOnEvent
			} else {
				GuiControl -g, % this.HWND ; removes the function object bound to the control
				this.menuOnEvent := ""
			}
		return value
		}
		get {
		return !this._enabled
		}
	}
	matchModeRegEx := true
	startAt {
		set {
		return this._startAt := (value > 0) ? value : this._startAt
		}
		get {
		return this._startAt
		}
	}
	delimiter {
		set {
		return this._delimiter := (StrLen(value) = 1) ? value : this._delimiter
		}
		get {
		return this._delimiter
		}
	}

	; ============================/ public properties ============================

	; ============================ private properties /============================

	_enabled := ""
	_delimiter := "`n"
	_startAt := 2
	_onEvent := ""
	_menuOnEvent := ""
	_szHwnd := ""

	; ============================/ private properties ============================

	; ============================ public methods /============================

	__New(_GUIID, _options:="") {

	static _defaultSettings :=
	(LTrim Join C
		{
			options: "Section w150 h35 Multi", ; edit control's options
			onEvent: "", ; edit control's g-label (function)
			menuOptions: "ys h130 w110 -VScroll", ; listbox control's options
			menuOnEvent: "", ; listbox control's g-label (function)
			menuFontOptions: "",
			menuFontName: "",
			disabled: false,
			delimiter: "`n", ; the delimiter used by the word list
			startAt: 2, ; the minimum number of characters a user must type before a search is performed. Zero is useful for local data with just a few items, but a higher value should be used when a single character search could match a few thousand items
			matchModeRegEx: true, ; if set to true, an occurrence of the wildcard character in the middle of a string will be interpreted not literally but as a regular expression (dot-star pattern)
			appendHapax: false ; append hapax legomena ?
		}
	)
	for _option, _value in _options, _params := new _defaultSettings
		_params[_option] := _value

		; Gui % _GUIID . ":+LastFoundExist"
		; IfWinNotExist
			; return !ErrorLevel:=1
		_detectHiddenWindows := A_DetectHiddenWindows
		DetectHiddenWindows, On
		if not (WinExist("ahk_id " . _GUIID))
			return !ErrorLevel:=1
		DetectHiddenWindows % _detectHiddenWindows

		RegExMatch(_params.options, "Pi)(^|\s)\K\+?[^-]Resize(?=\s|$)", _resize) ; _resize contains 'true' if the 'Resize' option is specified
		GUI, % _GUIID . ":Add", Edit, % _params.options . " hwnd_ID +Multi",
		this.AHKID := "ahk_id " . this.HWND:=_ID
		if (_resize) {

			GuiControlGet, _pos, Pos, % _ID
			GUI, % _GUIID . ":Add", Text, % "0x12 w11 h11 x" . _posx + _posw - 7 . " y" . _posy + _posh - 7 . " hwnd_ID", % Chr(9698) ; https://unicode-table.com/fr/25E2/
			this._szHwnd := _ID
			_fn := this.__resize.bind(this)
			GuiControl +g, % _ID, % _fn ; set the function object which handles the static control's events

		}
		GUI, % _GUIID . ":Font", % _params.menuFontOptions, % _params.menuFontName
		GUI, % _GUIID . ":Add", ListBox, % _params.menuOptions . " hwnd_ID",
		this.menu.AHKID := "ahk_id " . (this.menu.HWND:=_ID)

		_options.remove("disabled")
		for _option, _value in _options
			this[_option] := _params[_option]
		this.disabled := _params.disabled ; both 'onEvent' and 'menuOnEvent' properties must be set prior to set the 'disabled' one

	}
	addSourceFromFile(_source, _fileFullPath) {
		_list := (_f:=FileOpen(_fileFullPath, 4+0, "UTF-8")).read() ; EOL: 4 > replace `r`n with `n when reading
		if (A_LastError)
			return !ErrorLevel:=1, _f.close()
			this.addSource(_source, _list, _fileFullPath)
		return !ErrorLevel:=0, _f.close()
	}
	addSource(_source, _list, _fileFullPath:="") {

		_sources := eAutocomplete.sources
		_source := _sources[_source] := {path: _fileFullPath}

		_list := "`n" . _list . "`n"
		Sort, _list, D`n U
		ErrorLevel := 0
		_list := _source.list := LTrim(_list, "`n")

		while ((_letter:=SubStr(_list, 1, 1)) && _pos:=RegExMatch(_list, "Psi)\Q" . _letter . "\E.*\n\Q" . _letter . "\E.+?\n", _length)) {
			_source[_letter] := SubStr(_list, 1, _pos + _length - 1), _list := SubStr(_list, _pos + _length)
		} ; builds a dictionary from the list

	}
	setSource(_source) {
	if (eAutocomplete.sources.hasKey(_source)) {
		GuiControl,, % this.menu.HWND, % this.delimiter
		GuiControl,, % this.HWND,
	return !ErrorLevel:=0, this.source := _source
	}
	return !ErrorLevel:=1
	}

	menuSetSelection(_prm) {

		if (this.disabled or !Round(_prm) + 0)
	return
		_menu := this.menu
		if (_prm > 0) {
			SendMessage, % 0x18B, 0, 0,, % _menu.AHKID ; LB_GETCOUNT
			Control, Choose, % (_menu._selectedItem < ErrorLevel) ? ++_menu._selectedItem : ErrorLevel,, % _menu.AHKID
		} else Control, Choose, % (_menu._selectedItem - 1 > 0) ? --_menu._selectedItem : 1,, % _menu.AHKID
		this._endWord()

	}

		dispose() {
			GuiControl -g, % this.HWND ; removes the function object bound to the control
			this._onEvent := ""
			this.menuOnEvent := ""
			if (this.hasKey("_szHwnd"))
				GuiControl -g, % this._szHwnd ; removes the function object bound to the control
			this._onSize := ""
		}

	; ============================/ public methods ============================

	; ============================ private methods /============================

	_getSelection(ByRef _startSel:="", ByRef _endSel:="") { ; cf. https://github.com/dufferzafar/Autohotkey-Scripts/blob/master/lib/Edit.ahk
		VarSetCapacity(_startPos, 4, 0), VarSetCapacity(_endPos, 4, 0)
		SendMessage 0xB0, &_startPos, &_endPos,, % this.AHKID ; EM_GETSEL
		_startSel := NumGet(_startPos), _endSel := NumGet(_endPos)
	return _endSel
	}
	_suggestWordList(_hwnd) {

		ControlGetText, _input,, % this.AHKID
		_s := this._getSelection(), _menu := this.menu

		_match := ""
		_vicinity := SubStr(_input, _s, 2) ; the two characters in the vicinity of the current caret/insert position
		_leftSide := SubStr(_input, 1, _s)
		if ((StrLen(RegExReplace(_vicinity, "\s$")) <= 1)
			&& (RegExMatch(_leftSide, "\S+(?P<IsWord>\s?)$", _m))
			&& (StrLen(_m) >= this.startAt)) {
				if (_mIsWord) { ; if the word is completed...
					if (this.appendHapax && !InStr(_m, "*")) {
						ControlGet, _choice, Choice,,, % _menu.AHKID
						if not ((_m:=RTrim(_m, A_Space)) = _choice) ; if it is not suggested...
							this.__hapax(SubStr(_m, 1, 1), _m) ; append it to the dictionary
					}
				} else if (_letter:=SubStr(_m, 1, 1)) {
					if (_str:=this.sources[ this.source ][_letter]) {
						if (InStr(_m, "*") && this.matchModeRegEx && (_parts:=StrSplit(_m, "*")).length() = 2) { ; if 'matchModeRegEx' is set to true, an occurrence of the wildcard character in the middle of a string will be interpreted not literally but as a regular expression (dot-star pattern)
							_match := RegExReplace(_str, "`ami)^(?!" _parts.1 ".*" _parts.2 ").*\n") ; many thanks to AlphaBravo for this regex
							((this.delimiter <> "`n") && _match := StrReplace(_match, "`n", this.delimiter))
						} else {
							RegExMatch("$`n" . _str, "i)\n\K\Q" . _m . "\E.*\n\Q" . _m . "\E.+?(?=\n)", _match)
							((this.delimiter <> "`n") && _match := StrReplace(_match, "`n", this.delimiter))
						}
					}
				}
		}

		GuiControl,, % _menu.HWND, % this.delimiter . _match
		GuiControl, Choose, % _menu.HWND, % _menu._selectedItem:=0

		; ===================================================================
		(this._onEvent && this._onEvent.call(this, _input))
		; ===================================================================

	}
	_endWord() {

		ControlGetText, _input,, % this.AHKID
		GuiControlGet, _selection,, % this.menu.HWND
		_selection := Trim(_selection)
		_s := this._getSelection(), _leftSide := SubStr(_input, 1, _s), _rightSide := SubStr(_input, _s + 1)
		_pos := RegExMatch(_leftSide, "P)\S+$", _length)
		StringTrimRight, _leftSide, % _leftSide, % _length
		ControlSetText,, % _leftSide . _selection . _rightSide . A_Space, % this.AHKID
		SendMessage, 0xB1, % _pos + 1, % _s + StrLen(_selection) - _length,, % this.AHKID ; EM_SETSEL (https://msdn.microsoft.com/en-us/library/windows/desktop/bb761661(v=vs.85).aspx)

	}
	__hapax(_letter, _value) {

		if ((_source:=this.sources[ this.source ]).hasKey(_letter))
			_source.list := StrReplace(_source.list, _source[_letter], "")
		else _source[_letter] := ""
		_v := _source[_letter] . _value . "`n"
		Sort, _v, D`n U
		_source.list .= (_source[_letter]:=_v)
		if (_source.path <> "") {
			(_f:=FileOpen(_source.path, 4+1, "UTF-8")).write(LTrim(_source.list, "`n")), _f.close() ; EOL: 4 > replace `n with `r`n when writing
		}

	}

	__resize(_hwnd) {

		_coordModeMouse := A_CoordModeMouse
		CoordMode, Mouse, Client

		GuiControlGet, _pos, Pos, % _ID:=this.HWND
		_x := _posx, _y := _posy, _minSz := this.minSize, _maxSz := this.maxSize

		while (GetKeyState("LButton", "P")) {
			MouseGetPos, _mousex, _mousey
			_w := _mousex - _x, _h := _mousey - _y
			if (_w <= _minSz.w)
				_w := _minSz.w
			else if (_w >= _maxSz.w)
				_w := _maxSz.w
			if (_h <= _minSz.h)
				_h := _minSz.h
			else if (_h >= _maxSz.h)
				_h := _maxSz.h
			GuiControl, Move, % _ID, % "w" . _w . " h" . _h
			(this.onSize && this.onSize.call(A_GUI, this, _w, _h, _mousex, _mousey))
			GuiControlGet, _pos, Pos, % _ID
			GuiControl, MoveDraw, % _hwnd, % "x" . (_posx + _posw - 7) . " y" . (_posy + _posh - 7)
		sleep, 15
		}
		CoordMode, Mouse, % _coordModeMouse

	}

	; ============================/ private methods ============================

}
