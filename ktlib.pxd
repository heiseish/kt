#cython: language_level=3, c_string_type=unicode, c_string_encoding=utf8, boundscheck=False, cdivision=True, wraparound=False
# distutils: language=c++
from libcpp.string cimport string
from libcpp.vector cimport vector
from libcpp cimport bool as bool_t

cpdef string color_cyan(const string& text) nogil
cpdef string color_green(const string& text) nogil
cpdef string color_red(const string& text) nogil

cdef void make_list_equal(vector[string]& lhs, vector[string]& rhs, string pad_element=*) nogil

cdef class Action:
    cdef:
        string config_path
        object cfg
        object cookies
        string kt_config
        
    cdef read_config_from_file(self)
    cdef login(self)
    cdef string get_problem_url(self)
    cdef string get_problem_id(self)
    cdef string get_url(self, const string& option, string default = *)
    cdef _act(self)

cpdef void write_samples(tuple sample_data)

cdef class Gen(Action):
    ''' Handle `gen` command for kt_tool '''
    cdef:
        string _problem_id
        string _url 

    cdef _gen_samples(self)
    cdef _act(self)

cdef bool_t compare_entity(const string& lhs, const string& rhs, string& diff) nogil

cdef class Test(Action):
    cdef:
        string file_name
        string pre_script
        string script
        string post_script
        string lang

    cdef detect_file_name(self)
    cdef _act(self)