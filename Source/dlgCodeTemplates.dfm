inherited CodeTemplates: TCodeTemplates
  Left = 340
  Top = 192
  HelpContext = 540
  Caption = 'Code Templates'
  ClientHeight = 426
  ClientWidth = 554
  ShowHint = True
  OnClose = FormClose
  OnDestroy = FormDestroy
  OnShow = FormShow
  ExplicitWidth = 560
  ExplicitHeight = 455
  PixelsPerInch = 96
  TextHeight = 13
  object Panel: TPanel
    Left = 0
    Top = 0
    Width = 554
    Height = 426
    Align = alClient
    TabOrder = 0
    DesignSize = (
      554
      426)
    object btnAdd: TButton
      Left = 13
      Top = 118
      Width = 101
      Height = 24
      Action = actAddItem
      Images = vilImages
      TabOrder = 3
    end
    object btnDelete: TButton
      Left = 118
      Top = 118
      Width = 101
      Height = 24
      Action = actDeleteItem
      Images = vilImages
      TabOrder = 4
    end
    object btnMoveup: TButton
      Left = 224
      Top = 118
      Width = 101
      Height = 24
      Action = actMoveUp
      Images = vilImages
      TabOrder = 5
    end
    object btnMoveDown: TButton
      Left = 330
      Top = 118
      Width = 101
      Height = 24
      Action = actMoveDown
      Images = vilImages
      TabOrder = 6
    end
    object btnUpdate: TButton
      Left = 436
      Top = 118
      Width = 101
      Height = 24
      Action = actUpdateItem
      Images = vilImages
      TabOrder = 7
    end
    object btnCancel: TButton
      Left = 387
      Top = 394
      Width = 75
      Height = 25
      Anchors = [akRight, akBottom]
      Cancel = True
      Caption = '&Cancel'
      ModalResult = 2
      TabOrder = 9
    end
    object btnOK: TButton
      Left = 303
      Top = 394
      Width = 75
      Height = 25
      Anchors = [akRight, akBottom]
      Caption = '&OK'
      Default = True
      ModalResult = 1
      TabOrder = 1
    end
    object btnHelp: TButton
      Left = 471
      Top = 394
      Width = 75
      Height = 25
      Anchors = [akRight, akBottom]
      Caption = '&Help'
      TabOrder = 8
      OnClick = btnHelpClick
    end
    object GroupBox: TGroupBox
      AlignWithMargins = True
      Left = 3
      Top = 148
      Width = 548
      Height = 239
      Anchors = [akLeft, akTop, akRight]
      Caption = 'Code Template:'
      TabOrder = 2
      DesignSize = (
        548
        239)
      object Label1: TLabel
        Left = 8
        Top = 21
        Width = 31
        Height = 13
        Caption = '&Name:'
      end
      object Label2: TLabel
        Left = 8
        Top = 65
        Width = 48
        Height = 13
        Caption = '&Template:'
      end
      object Label5: TLabel
        Left = 8
        Top = 44
        Width = 57
        Height = 13
        Caption = '&Description:'
      end
      object Label4: TLabel
        Left = 8
        Top = 200
        Width = 204
        Height = 13
        Caption = 'Press Shift+Ctrl+M for Modifier completion'
        Enabled = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'MS Shell Dlg 2'
        Font.Style = []
        ParentFont = False
      end
      object Label3: TLabel
        Left = 8
        Top = 215
        Width = 214
        Height = 13
        Caption = 'Press Shift+Ctrl+P for Parameter completion'
        Enabled = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'MS Shell Dlg 2'
        Font.Style = []
        ParentFont = False
      end
      object SynTemplate: TSynEdit
        Left = 9
        Top = 84
        Width = 532
        Height = 116
        Anchors = [akLeft, akTop, akRight]
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Courier New'
        Font.Pitch = fpFixed
        Font.Style = []
        Font.Quality = fqClearTypeNatural
        TabOrder = 1
        UseCodeFolding = False
        Gutter.Font.Charset = DEFAULT_CHARSET
        Gutter.Font.Color = clWindowText
        Gutter.Font.Height = -11
        Gutter.Font.Name = 'Courier New'
        Gutter.Font.Style = []
        Gutter.Width = 0
        TabWidth = 4
      end
      object edDescription: TEdit
        Left = 115
        Top = 43
        Width = 426
        Height = 21
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 2
      end
      object edShortcut: TEdit
        Left = 115
        Top = 16
        Width = 121
        Height = 21
        TabOrder = 0
        OnKeyPress = edShortcutKeyPress
      end
    end
    object lvItems: TListView
      Left = 1
      Top = 1
      Width = 552
      Height = 109
      Align = alTop
      Columns = <
        item
          Caption = 'Name'
          Width = 120
        end
        item
          Caption = 'Description'
          Width = 280
        end>
      ColumnClick = False
      HideSelection = False
      ReadOnly = True
      RowSelect = True
      TabOrder = 0
      ViewStyle = vsReport
      OnDeletion = lvItemsDeletion
      OnSelectItem = lvItemsSelectItem
    end
  end
  object ActionList: TActionList
    Images = vilImages
    OnUpdate = ActionListUpdate
    Left = 379
    Top = 27
    object actAddItem: TAction
      Caption = '&Add'
      Hint = 'Add item'
      ImageIndex = 4
      ImageName = 'Item50'
      OnExecute = actAddItemExecute
    end
    object actDeleteItem: TAction
      Caption = '&Delete'
      Hint = 'Delete item'
      ImageIndex = 0
      ImageName = 'Item15'
      OnExecute = actDeleteItemExecute
    end
    object actMoveUp: TAction
      Caption = '&Up'
      Hint = 'Move item up'
      ImageIndex = 2
      ImageName = 'Item48'
      OnExecute = actMoveUpExecute
    end
    object actMoveDown: TAction
      Caption = '&Down'
      Hint = 'Move item down'
      ImageIndex = 3
      ImageName = 'Item49'
      OnExecute = actMoveDownExecute
    end
    object actUpdateItem: TAction
      Caption = '&Update'
      Hint = 'Update item'
      ImageIndex = 1
      ImageName = 'Item40'
      OnExecute = actUpdateItemExecute
    end
  end
  object vilImages: TVirtualImageList
    DisabledGrayscale = False
    DisabledSuffix = '_Disabled'
    Images = <
      item
        CollectionIndex = 14
        CollectionName = 'Item15'
        Disabled = False
        Name = 'Item15'
      end
      item
        CollectionIndex = 39
        CollectionName = 'Item40'
        Disabled = False
        Name = 'Item40'
      end
      item
        CollectionIndex = 47
        CollectionName = 'Item48'
        Disabled = False
        Name = 'Item48'
      end
      item
        CollectionIndex = 48
        CollectionName = 'Item49'
        Disabled = False
        Name = 'Item49'
      end
      item
        CollectionIndex = 49
        CollectionName = 'Item50'
        Disabled = False
        Name = 'Item50'
      end>
    ImageCollection = CommandsDataModule.icImages
    Left = 320
    Top = 27
  end
end
