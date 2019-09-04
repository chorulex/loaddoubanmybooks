#!/bin/bash

# 该脚本用于自动从豆瓣抓取你的账户下的所有读书清单，包括
# 在读，已读和想读
# 完成后保存到douban-book-list.csv文件，该文件可以使用excel程序打开查看

readonly cookies_file="cookie.txt"
readonly book_count_one_page=15

# 先设置好的豆瓣账户和密码，然后再运行
readonly user_name=""
readonly user_pwd=""

people_id=
people_name=
book_page_count=

function login()
{
    file_name="login_res.html"
    wget -q --post-data="ck=&name=${user_name}&password=${user_pwd}&remember=false&ticket=" \
        --save-cookies=${cookies_file} --keep-session-cookies \
        https://accounts.douban.com/j/mobile/login/basic \
        -O ${file_name}

    sed -i 's/,/,\n/g' ${file_name}
    sed -i 's/{/\n{/g' ${file_name}
    #cat ${file_name}

    login_status=$(grep status ${file_name} | awk -F"\"" {'print $4'})
    # exit if fail to login
    if [[ ${login_status} == "failed" ]]; then
        echo "登录失败！原因："
        grep description ${file_name} | awk -F"\"" {'print $4'}

        exit
    fi

    people_id=$(grep \"id\" ${file_name} | awk -F"\"" {'print $4'})
    people_name=$(grep name ${file_name} | awk -F"\"" {'print $4'})

    rm ${file_name}
    echo "[$(date)] success to login. $people_id: ${people_name}"
}

function extract_page_count()
{
    type_key=$1

    extract_book_count ${type_key}
    book_count=$?
    if [[ ${book_count} -eq 0 ]]; then
        book_page_count=0
    elif [[ ${book_count} -le ${book_count_one_page} ]]; then
        book_page_count=1
    else
        grep "<a href=\"/people/${people_id}/${type_key}?start=" book_first_page.html | \
            grep -n ">[1-9]*<" > wish_page_list
        #cat wish_page_list
        book_page_count=$(tail -n 1 wish_page_list | awk -F '>' {'print $2'} | awk -F '<' {'print $1'})

        rm wish_page_list
    fi

    echo "[$(date)] ${type_key} book count: ${book_count}, page_count: ${book_page_count}"
}

# 从文件中 截取book list到文件book_List.html
function extract_book_list_context()
{
    file=$1

    line_begin=$(grep -n "<ul class=\"interest-list\"" ${file} | awk -F ":" {'print $1'})
    sed -n ''"${line_begin}"',$p' $file > book_list.html

    line_end=$(grep -n "</ul>" book_list.html |head -n 1 | awk -F ":" {'print $1'})
    sed -i -n '1,'"${line_end}"'p' book_list.html
}

# 判断账户是否安全，如果不安全则退出程序！
function detect_account_safe()
{
    detect_str=$(grep "account-wrap" book_first_page.html)
    #echo ${detect_str}
    if [[ ${detect_str}"x" != "x" ]]; then
        echo "[$(date)] ！！！你的账户已被锁定！！！请手动解锁，然后重新执行！"
        exit
    fi
}

function download_book_first_page()
{
    #wget -q --header="User-Agent: Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36" \
    wget -q --load-cookies=${cookies_file} https://book.douban.com/people/${people_id}/$1 \
        -O book_first_page.html

    if [[ $? -ne 0 ]]; then
        echo "[$(date)] 下载文件失败！可能出现了严重问题！"
        exit
    fi

    if [[ ! -f book_first_page.html ]]; then
        echo "[$(date)] 下载文件失败！可能出现了严重问题！"
        exit
    fi

    detect_account_safe

    #删除空白行/空行
    sed -i -e '/^$/d' book_first_page.html
}

function download_book_list_page()
{
    type=$1
    page_num=$2

    if [[ ${page_num} -eq 0 ]]; then
        href="https://book.douban.com/people/${people_id}/${type}"
    else
        page_start=$(($page_num * 15))
        href="https://book.douban.com/people/${people_id}/${type}?start=${page_start}&sort=time&rating=all&filter=all&mode=grid"
    fi

    wget -q --load-cookies=${cookies_file} ${href} -O book_first_page.html

    if [[ $? -ne 0 ]]; then
        echo "[$(date)] 下载文件失败！可能出现了严重问题！"
        exit
    fi

    if [[ ! -f book_first_page.html ]]; then
        echo "[$(date)] 下载文件失败！可能出现了严重问题！"
        exit
    fi

    detect_account_safe

    #删除空白行/空行
    sed -i -e '/^$/d' book_first_page.html
}

# 将book详细信息截取出来保存到另外一个文件
function extract_book_details()
{
    line_begin=$(grep -n "<li class=\"subject-item\">" book_list.html | head -n 1 | awk -F ":" {'print $1'})
    line_end=$(grep -n "</li>" book_list.html | head -n 1 | awk -F ":" {'print $1'})

    #echo ${line_begin},${line_end}
    sed -n ''"${line_begin}"','"${line_end}"'p' book_list.html > $1
    line_end=$(($line_end+1))
    sed -i -n ''"${line_end}"',$p' book_list.html
}

function download_book_page()
{
    wget -q --load-cookies=${cookies_file} $1 -O book_page.html
}

function extract_book_info()
{
    book_stat_type=$1

    book_count=$(grep -n "<li class=\"subject-item\">" book_list.html | wc -l)
    echo "[$(date)] book count:${book_count}"

    for ((i=0; i<${book_count}; i++))
    do
        book_detail_file="book_details.html"
        extract_book_details ${book_detail_file}

        # reset
        author=
        translator=

        book_addr=$(grep "title=" ${book_detail_file} | awk -F "\"" {'print $2'})
        download_book_page ${book_addr}

        douban_score=$(grep "<strong class=\"ll rating_num \" property=\"v:average\">" book_page.html | awk -F">" {'print $2'} | awk -F"<" {'print $1'})
        douban_votes_count=$(grep "<span property=\"v:votes\">" book_page.html | awk -F">" {'print $3'} | awk -F"<" {'print $1'})
        book_group=$(grep "丛书:" book_page.html | head -n 1 | awk -F">" {'print $4'} | awk -F"<" {'print $1'})
        book_page=$(grep "页数:" book_page.html | head -n 1 | awk -F">" {'print $3'} | awk -F"<" {'print $1'})
        publisher=$(grep "出版社:" book_page.html | head -n 1 | awk -F">" {'print $3'} | awk -F"<" {'print $1'} | sed 's/,/-/g')
        pub_date=$(grep "出版年:" book_page.html | head -n 1 | awk -F">" {'print $3'} | awk -F"<" {'print $1'})
        charge=$(grep "定价:" book_page.html | head -n 1 | awk -F">" {'print $3'} | awk -F"<" {'print $1'})
        book_isbn=$(grep "ISBN:" book_page.html | head -n 1 | awk -F">" {'print $3'} | awk -F"<" {'print $1'})
        book_origin_name=$(grep "原作名:" book_page.html | head -n 1 | awk -F">" {'print $3'} | awk -F"<" {'print $1'} | sed 's/,/./g')

        book_title=$(grep "title=" ${book_detail_file} | awk -F "\"" {'print $4'})
        book_sub_title=$(grep "副标题:" book_page.html | head -n 1 | awk -F">" {'print $3'} | awk -F"<" {'print $1'})
        if [[ ${book_sub_title}"x" == "x" ]]; then
            book_name=${book_title}
        else
            book_name=${book_title}":"${book_sub_title}
        fi

        # extract book description, include publisher/author/version
        line_begin=$(grep -n "<div class=\"pub\">" ${book_detail_file} | head -n 1 | awk -F ":" {'print $1'})
        sed -n ''"${line_begin}"',$p' ${book_detail_file} > book-description.html
        line_end=$(grep -n "</div>" book-description.html | head -n 1 | awk -F ":" {'print $1'})
        line_end=$(($line_end-1))
        book_description=$(sed -n '2,'"${line_end}"'p' book-description.html | grep "/" | sed 's/,/./g')
        #echo ${book_description}

        author=$(echo -e ${book_description} | awk -F"/" {'print $1'})
        item_num=$(echo -e ${book_description} | awk -F"/" {'print NF'})
        #echo $item_num
        if [[ $item_num == 5 ]]; then
            translator=$(echo -e ${book_description} | awk -F"/" {'print $2'})
        fi

        # extract book tags
        book_tags=$(grep "<span class=\"tags\">" ${book_detail_file} | awk -F":" {'print $2'} | awk -F"<" {'print $1'})

        if [[ ${book_stat_type} == "wish" ]] ; then
            book_line=${book_name}","${book_origin_name}","${author}","${translator}","${publisher}","${book_group}","${pub_date}","${book_isbn}","${book_page}","${charge}","${book_tags}",想读,"${douban_score}","${douban_votes_count}","${book_addr}
        elif [[ ${book_stat_type} == "do" ]] ; then
            book_line=${book_name}","${book_origin_name}","${author}","${translator}","${publisher}","${book_group}","${pub_date}","${book_isbn}","${book_page}","${charge}","${book_tags}",在读,"${douban_score}","${douban_votes_count}","${book_addr}
        elif [[ ${book_stat_type} == "collect" ]] ; then
            book_line=${book_name}","${book_origin_name}","${author}","${translator}","${publisher}","${book_group}","${pub_date}","${book_isbn}","${book_page}","${charge}","${book_tags}",已读,"${douban_score}","${douban_votes_count}","${book_addr}
        fi
        echo ${book_line} >> book-list

        rm book-description.html
        rm book_page.html
        rm ${book_detail_file}
    done
    rm book_list.html
}

function extract_book_count()
{
    book_count_this_type=
    if [[ $1 == "wish" ]] ; then
        book_count_this_type=$(grep "我想读的书" book_first_page.html | head -n 1 | awk -F"(" {'print $2'} | awk -F")" {'print $1'})
    elif [[ $1 == "do" ]] ; then
        book_count_this_type=$(grep "我在读的书" book_first_page.html | head -n 1 | awk -F"(" {'print $2'} | awk -F")" {'print $1'})
    elif [[ $1 == "collect" ]] ; then
        book_count_this_type=$(grep "我读过的书" book_first_page.html | head -n 1 | awk -F"(" {'print $2'} | awk -F")" {'print $1'})
    fi

    return ${book_count_this_type}
}

function load_books()
{
    type_name=$1

    download_book_first_page ${type_name}
    extract_page_count ${type_name}

    if [[ ${book_page_count} -eq 0 ]]; then
        return
    fi

    for ((num=0; num<${book_page_count}; num++))
    do
        echo "[$(date)] downloading ${type_name} book page $num"
        download_book_list_page ${type_name} $num
        extract_book_list_context "book_first_page.html"
        extract_book_info ${type_name}

        rm book_first_page.html
    done

    echo "[$(date)] finish to load all ${type_name} books, save to file douban-book-list.csv"
}

function load_my_all_books()
{
    echo "书名,原书名,作者,翻译,出版社,丛书,出版日期,ISBN,页数,定价,标签,阅读状态,豆瓣评分,豆瓣评论人数,豆瓣地址" > book-list

    book_types=("do" "wish" "collect")
    for type_name in ${book_types[*]}
    do
        load_books ${type_name}
    done

    cat book-list > douban-book-list.csv
    rm book-list
}

login
load_my_all_books
