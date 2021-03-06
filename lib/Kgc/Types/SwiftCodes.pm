package Kgc::Types::SwiftCodes;

use strict;
use warnings;
use utf8;
use constant {
	NATIVENAME   => 0,
	SWIFTCODE   => 1,
	ENGLISHNAME   => 2,
	COUNTRY => 3
};

our $mapper;

BEGIN{
	open(my $fh1,'<',DATA);
	my $i = 0;
	while(<$fh1>){
		chomp($_);
		my @cols = split("\t",$_);
		my $colref = \@cols;
		$mapper->{'NATIVENAME'}->{$cols[NATIVENAME]} = $colref;
		$mapper->{'SWIFTCODE'}->{$cols[SWIFTCODE]} = $colref;
		$mapper->{'ENGLISHNAME'}->{$cols[ENGLISHNAME]} = $colref;
		
	}
	close(DATA);
}



=pod

---+ getdata('NATIVENAME','みずほ銀行','ENGLISHNAME')->'MIZUHO BANK LTD.'

fetch(bywhat,what,forwhat)

=cut

sub getdata{
	my ($x,$y,$z) = @_;
	return undef unless defined $x && $x =~ m/^(NATIVENAME|SWIFTCODE|ENGLISHNAME)$/;
	return undef unless defined $z && $z =~ m/^(NATIVENAME|SWIFTCODE|ENGLISHNAME|COUNTRY)$/;
	return undef unless defined $y;
	my $colref = $mapper->{$x}->{$y};
	return undef unless defined $colref;
	my $maps = {
		'NATIVENAME' => NATIVENAME, 'SWIFTCODE' => SWIFTCODE, 'ENGLISHNAME' =>  ENGLISHNAME,
		'COUNTRY' => COUNTRY
	};
	return $colref->{$x}->{$y}->[$maps->{$z}];
}


__DATA__
みずほ銀行	MHCBJPJT	MIZUHO BANK LTD.	JP
三菱東京UFJ銀行	BOTKJPJT	BANK OF TOKYO MITSUBISHI UFJ LTD. THE	JP
三井住友銀行	SMBCJPJT	SUMITOMO MITSUI BANKING CORPORATION	JP
りそな銀行	DIWAJPJT	RESONA BANK LTD. TOKYO	JP
みずほコーポレート銀行	MHCBJPJT	MIZUHO BANK LTD.	JP
埼玉りそな銀行	SAIBJPJT	SAITAMA RESONA BANK LIMITED	JP
ソニー銀行	SNYBJPJT	SONY BANK INC.	JP
楽天銀行	RAKTJPJT	RAKUTEN BANK LTD.	JP
住信SBIネット銀行	NTSSJPJT	SBI SUMISHIN NET BANK LTD.	JP
じぶん銀行	JICRJPJ1	JIBUN BANK CORPORATION	JP
大和ネクスト銀行	DNEXJPJT	DAIWA NEXT BANK LTD.	JP
北海道銀行	HKDBJPJT	HOKKAIDO BANK LTD. THE	JP
青森銀行	AOMBJPJT	AOMORI BANK LTD. THE	JP
みちのく銀行	MCHIJPJT	MICHINOKU BANK LTD. THE	JP
秋田銀行	AKITJPJT	AKITA BANK LTD. THE	JP
北都銀行	HOKBJPJT	HOKUTO BANK LTD. THE	JP
荘内銀行	SNAIJPJT	SHONAI BANK LTD. THE	JP
山形銀行	YAMBJPJT	YAMAGATA BANK LTD. THE	JP
岩手銀行	BAIWJPJT	BANK OF IWATE LTD. THE	JP
東北銀行	TOHKJPJ1	THE TOHOKU BANK LTD	JP
七十七銀行	BOSSJPJT	THE 77 BANK LTD.	JP
東邦銀行	TOHOJPJT	TOHO BANK LTD. THE	JP
群馬銀行	GUMAJPJT	GUNMA BANK LTD. THE	JP
足利銀行	ASIKJPJT	ASHIKAGA BANK	JP
常陽銀行	JOYOJPJT	JOYO BANK LTD. THE	JP
筑波銀行	KGBKJPJT	TSUKUBA BANK LTD.	JP
武蔵野銀行	MUBKJPJT	MUSASHINO BANK LTD. THE	JP
千葉銀行	CHBAJPJT	CHIBA BANK LTD. THE	JP
千葉興業銀行	CHIKJPJT	CHIBA KOGYO BANK LTD. THE	JP
東京都民銀行	TOMIJPJT	TOKYO TOMIN BANK LIMITED THE	JP
横浜銀行	HAMAJPJT	BANK OF YOKOHAMA LTD. THE	JP
第四銀行	DAISJPJT	DAISHI BANK LTD. THE	JP
北越銀行	HETSJPJT	HOKUETSU BANK LTD. THE	JP
山梨中央銀行	YCHBJPJT	YAMANASHI CHUO BANK LTD. THE	JP
八十二銀行	HABKJPJT	HACHIJUNI BANK LTD. THE	JP
北陸銀行	RIKBJPJT	HOKURIKU BANK LTD. THE	JP
北國銀行	HKOKJPJT	HOKKOKU BANK LTD. THE	JP
福井銀行	FKUIJPJT	FUKUI BANK LTD. THE	JP
静岡銀行	SHIZJPJT	SHIZUOKA BANK LTD. THE	JP
スルガ銀行	SRFXJPJT	SURUGA BANK LTD. THE	JP
清水銀行	SMZGJPJT	SHIMIZU BANK LTD. THE	JP
大垣共立銀行	OGAKJPJT	OGAKI KYORITSU BANK LTD. THE	JP
十六銀行	JUROJPJT	JUROKU BANK LTD. THE	JP
三重銀行	MIEBJPJT	MIE BANK LTD. THE	JP
百五銀行	HYKGJPJTTSU	HYAKUGO BANK LTD. THE	JP
滋賀銀行	SIGAJPJT	SHIGA BANK LTD. THE	JP
京都銀行	BOKFJPJZ	BANK OF KYOTO LTD. THE	JP
近畿大阪銀行	OSABJPJS	KINKI OSAKA BANK LTD. THE	JP
池田泉州銀行	BIKEJPJS	THE SENSHU IKEDA BANK LTD.	JP
南都銀行	NANTJPJT	NANTO BANK LTD THE	JP
紀陽銀行	KIYOJPJT	KIYO BANK LTD THE	JP
但馬銀行	TJMAJPJZ	TAJIMA BANK LTD THE	JP
鳥取銀行	BIRDJPJZ	TOTTORI BANK LTD. THE	JP
山陰合同銀行	SGBKJPJT	SAN IN GODO BANK LTD. THE	JP
中国銀行	CHGKJPJZ	CHUGOKU BANK LTD. THE	JP
広島銀行	HIROJPJT	HIROSHIMA BANK LTD. THE	JP
山口銀行	YMBKJPJT	YAMAGUCHI BANK LTD. THE	JP
阿波銀行	AWABJPJT	AWA BANK LTD. THE	JP
百十四銀行	HYAKJPJT	HYAKUJUSHI BANK LTD. THE	JP
伊予銀行	IYOBJPJT	IYO BANK LTD. THE	JP
四国銀行	SIKOJPJT	SHIKOKU BANK LTD. THE	JP
福岡銀行	FKBKJPJT	BANK OF FUKUOKA LTD. THE	JP
筑邦銀行	CHIHJPJT	THE CHIKUHO BANK LTD.	JP
佐賀銀行	BKSGJPJT	BANK OF SAGA LTD. THE	JP
十八銀行	EITNJPJT	EIGHTEENTH BANK LIMITED THE	JP
親和銀行	SHWAJPJT	SHINWA BANK LTD. THE	JP
肥後銀行	HIGOJPJT	THE HIGO BANK LIMITED	JP
大分銀行	OITAJPJT	OITA BANK LTD. THE	JP
宮崎銀行	MIYAJPJT	MIYAZAKI BANK LTD. THE	JP
鹿児島銀行	KAGOJPJT	KAGOSHIMA BANK LTD. THE	JP
琉球銀行	RYUBJPJZ	BANK OF THE RYUKYUS LTD.	JP
沖縄銀行	BOKIJPJZ	BANK OF OKINAWA LTD. THE	JP
西日本シティ銀行	NISIJPJT	THE NISHI NIPPON CITY BANK LTD	JP
北九州銀行	KITQJPJ1	KIMURA SECURITIES CO. LTD.	JP
三菱UFJ信託銀行	MTBCJPJT	MITSUBISHI UFJ TRUST AND BANKING CORPORATION	JP
みずほ信託銀行	YTBCJPJT	MIZUHO TRUST AND BANKING CO. LTD.	JP
三井住友信託銀行	STBCJPJT	SUMITOMO MITSUI TRUST BANK LIMITED	JP
日本マスタートラスト信託銀行	MTBJJPJT	MASTER TRUST BANK OF JAPAN LTD THE	JP
ステート・ストリート信託銀行	SSTBJPJX	STATE STREET TRUST AND BANKING COMPANY LIMITED	JP
SMBC信託銀行	SGTBJPJT	SOCIETE GENERALE PRIVATE BANKING (JAPAN) LTD.	JP
野村信託銀行	NMTBJPJT	THE NOMURA TRUST AND BANKING CO. LTD.	JP
オリックス銀行	OTBCJPJT	OSAKA SHOKEN DAIKO CO. LT.	JP
しんきん信託銀行	SKTBJPJ1	SHINKIN TRUST BANK LTD.	JP
農中信託銀行	NCTBJPJ1	NORINCHUKIN TRUST AND BANKING CO. LTD. THE	JP
新生信託銀行	SHTCJPJ1	SHINSEI TRUST BANKING CO. LTD.	JP
日証金信託銀行	JSTCJPJ1	JSF TRUST AND BANKING CO. LTD	JP
新銀行東京	SGTKJPJT	SHINGINKO TOKYO LIMITED	JP
日本トラスティ・サービス信託銀行	JTSBJPJT	JAPAN TRUSTEE SERVICES BANK LTD.	JP
資産管理サービス信託銀行	TCSBJPJT	TRUST AND CUSTODY SERVICES BANK LTD.	JP
新生銀行	LTCBJPJT	SHINSEI BANK LTD.	JP
あおぞら銀行	NCBTJPJT	AOZORA BANK LTD	JP
シティバンク銀行	CITIJPJT	CITIBANK JAPAN LTD.	JP
KEBハナ銀行	KOEXJPJT	KOREA EXCHANGE BANK	JP
バンコック銀行	BKKBJPJT	BANGKOK BANK PUBLIC COMPANY LTD.	JP
ニューヨーク銀行	IRVTJPJX	THE BANK OF NEW YORK MELLON TOKYO BRANCH	JP
ユニオン・バンク・オブ・カリフォルニア	BOFCJPJT	BANK OF AMERICA TOKYO	JP
コメルツ銀行	COBAJPJX	COMMERZBANK AG TOKYO	JP
SBJ銀行	SHBKJPJX	SHINHAN BANK JAPAN	JP
トロント・ドミニオン銀行	TDOMJPJT	TORONTO DOMINION BANK	JP
ウリィ銀行	HVBKJPJT	WOORI BANK TOKYO	JP
(旧)ハナ銀行	HNBNJPJT	HANA BANK TOKYO BRANCH	JP
アイエヌジーバンク・エヌ・ヴイ	INGBJPJT	ING BANK N.V.	JP
中國銀行 （バンク・オブ・チャイナ）	BKCHJPJT	BANK OF CHINA	JP
北洋銀行	NORPJPJP	NORTH PACIFIC BANK LTD.	JP
きらやか銀行	SHIAJPJT	KIRAYAKA BANK LTD.	JP
北日本銀行	KNPBJPJT	KITA NIPPON BANK LTD. THE	JP
仙台銀行	SEDIJPJ1	THE SENDAI BANK LTD.	JP
福島銀行	FKSBJPJ1	THE FUKUSHIMA BANK LTD.	JP
大東銀行	DATTJPJ1	THE DAITO BANK LTD	JP
東和銀行	TOWAJPJT	TOWA BANK LTD. THE	JP
栃木銀行	TOCIJPJT	THE TOCHIGI BANK LTD.	JP
京葉銀行	KEIBJPJT	KEIYO BANK LTD. THE	JP
東日本銀行	HNPBJPJT	HIGASHI NIPPON BANK LIMITED THE	JP
東京スター銀行	TSBKJPJT	TOKYO STAR BANK LIMITED THE	JP
神奈川銀行	KANGJPJ1	THE KANAGAWA BANK LTD.	JP
大光銀行	TAIKJPJ1	THE TAIKO BANK LTD.	JP
長野銀行	NAGAJPJZ	NAGANO BANK LTD.	JP
富山第一銀行	FBTYJPJ1	FIRST BANK OF TOYAMA LTD.	JP
福邦銀行	FUHOJPJ1	THE FUKUHO BANK LTD	JP
岐阜銀行	GIFBJPJZ	GIFU SHINKIN BANK THE	JP
愛知銀行	AICHJPJN	AICHI BANK LTD. THE	JP
名古屋銀行	NAGOJPJN	BANK OF NAGOYA LTD. THE	JP
中京銀行	CKBKJPJN	CHUKYO BANK LIMITED THE	JP
第三銀行	DSBKJPJT	DAISAN BANK LTD. THE	JP
関西アーバン銀行	KSBJJPJS	KANSAI URBAN BANKING CORPORATION	JP
みなと銀行	HSINJPJK	MINATO BANK LTD THE (FORMERLY THE HANSHIN BANK LTD)	JP
島根銀行	SHMMJPJ1	THE SHIMANE BANK LTD.	JP
トマト銀行	TOMAJPJZ	TOMATO BANK LTD.	JP
もみじ銀行	HRSBJPJT	MOMIJI BANK LTD.	JP
西京銀行	SAKBJPJZ	SAIKYO BANK LTD. THE	JP
徳島銀行	TKSBJPJZ	TOKUSHIMA BANK LTD THE	JP
香川銀行	KGWBJPJZ	KAGAWA BANK LTD. THE	JP
愛媛銀行	HIMEJPJT	EHIME BANK LTD. THE	JP
高知銀行	KOTIJPJZ	THE BANK OF KOCHI LIMITED	JP
長崎銀行	NAGKJPJ1	NAGASAKI BANK	JP
熊本銀行	KUMAJPJZ	KUMAMOTO BANK LTD. THE	JP
豊和銀行	HOWAJPJT	THE HOWA BANK LTD	JP
宮崎太陽銀行	MITYJPJ1	THE MIYAZAKI TAIYO BANK LTD.	JP
南日本銀行	MINPJPJ1	THE MINAMI NIPPON BANK LTD.	JP
沖縄海邦銀行	OKWAJPJ1	OKINAWA KAIHO BANK	JP
八千代銀行	YACYJPJT	YACHIYO BANK LTD. THE	JP
韓国産業銀行	KODBJPJT	KOREA DEVELOPMENT BANK THE TOKYO BRANCH	JP
第一銀行 (台湾)	FCBKJPJT	FIRST COMMERCIAL BANK TOKYO BRANCH	JP
台湾銀行	BKTWJPJT	BANK OF TAIWAN TOKYO BRANCH	JP
交通銀行 (中国)	COMMJPJT	BANK OF COMMUNICATIONS TOKYO BRANCH	JP
中国工商銀行	ICBKCNBJ	MEGA INTERNATIONAL COMMERCIAL BANK CO. LTD.	JP
国民銀行 (韓国)	CZNBJPJT	KOOKMIN BANK	JP
信金中央金庫	ZENBJPJT	SHINKIN CENTRAL BANK	JP
横浜信用金庫	YOKOJPJM	YOKOHAMA SHINKIN BANK THE	JP
朝日信用金庫	ASKBJPJT	ASAHI SHINKIN BANK THE	JP
さわやか信用金庫	ZENBJPJT	SHINKIN CENTRAL BANK	JP
東京東信用金庫	CHSBJPJT	TOKYO HIGASHI SHINKIN BANK THE	JP
城南信用金庫	JSBKJPJT	JOHNAN SHINKIN BANK THE	JP
城北信用金庫	OJISJPJT	JOHOKU SHINKIN BANK THE	JP
巣鴨信用金庫	SSHBJPJT	SUGAMO SHINKIN BANK THE	JP
多摩信用金庫	TAMAJPJT	TAMA SHINKIN BANK THE	JP
岐阜信用金庫	GFSBJPJZ	GIFU SHINKIN BANK THE	JP
岡崎信用金庫	OKSBJPJZ	OKAZAKI SHINKIN BANK THE	JP
瀬戸信用金庫	SSBKJPJZ	SETO SHINKIN BANK THE	JP
京都信用金庫	KYSBJPJZ	KYOTO SHINKIN BANK THE	JP
京都中央信用金庫	KCHUJPJY	KYOTO CHUO SHINKIN BANK THE	JP
大阪市信用金庫	OSACJPJS	OSAKA CITY SHINKIN BANK THE	JP
尼崎信用金庫	AMASJPJZ	AMAGASAKI SHINKIN BANK THE	JP
大川信用金庫	OHSHJPJ1	THE OHKAWA SHINKIN BANK FUKUOKA JAPAN	JP
商工組合中央金庫	SKCKJPJT	SHOKO CHUKIN BANK LTD. THE	JP
全国信用協同組合連合会	ZSFBJPJ1	SHINKUMI FEDERATION BANK THE	JP
農林中央金庫	NOCUJPJT	NORINCHUKIN BANK THE	JP